import 'dart:math';
import 'package:flutter/foundation.dart';
import '../local/outbox_repository.dart';
import '../local/queue_local_repository.dart';

enum SyncFailureKind {
  unauthenticated,
  forbidden,
  validation,
  conflict,
  server,
  network,
  invalidResponse,
}

/// Response representation from backend order sync endpoint.
class SyncGatewayResponse {
  final bool isSuccess;
  final String? serverOrderId;
  final bool isDuplicate;
  final bool isPermanentError;
  final String? errorMessage;
  final SyncFailureKind? failureKind;

  const SyncGatewayResponse.success({
    required this.serverOrderId,
    this.isDuplicate = false,
  }) : isSuccess = true,
       isPermanentError = false,
       errorMessage = null,
       failureKind = null;

  const SyncGatewayResponse.transientError({
    required this.errorMessage,
    this.failureKind,
  }) : isSuccess = false,
       isPermanentError = false,
       serverOrderId = null,
       isDuplicate = false;

  const SyncGatewayResponse.permanentError({
    required this.errorMessage,
    this.failureKind,
  }) : isSuccess = false,
       isPermanentError = true,
       serverOrderId = null,
       isDuplicate = false;
}

/// Abstract contract for sending order mutations to backend API.
abstract class OrderSyncGateway {
  Future<SyncGatewayResponse> submitOrderMutation({
    required String idempotencyKey,
    required String payloadJson,
  });
}

/// Summary result of a batch synchronization run.
class SyncBatchResult {
  final int totalProcessed;
  final int syncedCount;
  final int transientErrorCount;
  final int permanentErrorCount;

  const SyncBatchResult({
    required this.totalProcessed,
    required this.syncedCount,
    required this.transientErrorCount,
    required this.permanentErrorCount,
  });

  bool get hasErrors => transientErrorCount > 0 || permanentErrorCount > 0;
}

/// State representation of the sync service for UI reactivity.
class SyncServiceState {
  final bool isSyncing;
  final int pendingCount;
  final int permanentFailureCount;
  final String? lastError;
  final DateTime? lastSyncedAt;

  const SyncServiceState({
    this.isSyncing = false,
    this.pendingCount = 0,
    this.permanentFailureCount = 0,
    this.lastError,
    this.lastSyncedAt,
  });

  SyncServiceState copyWith({
    bool? isSyncing,
    int? pendingCount,
    int? permanentFailureCount,
    String? lastError,
    DateTime? lastSyncedAt,
  }) {
    return SyncServiceState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      permanentFailureCount:
          permanentFailureCount ?? this.permanentFailureCount,
      lastError: lastError ?? this.lastError,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

/// SyncService coordinates the sequential, durable, idempotent background
/// synchronization of offline mutations.
/// Fulfills Issue #33 Acceptance Criteria #1, #2, #3, and #4.
class SyncService extends ChangeNotifier {
  final OutboxRepository outboxRepo;
  final QueueLocalRepository queueRepo;
  final OrderSyncGateway gateway;

  final Duration baseDelay;
  final Duration maxDelay;

  SyncServiceState _state = const SyncServiceState();
  SyncServiceState get state => _state;

  SyncService({
    required this.outboxRepo,
    required this.queueRepo,
    required this.gateway,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
  });

  /// Computes exponential backoff delay based on retry attempt: baseDelay * 2^retry.
  Duration calculateBackoff(int retryCount) {
    final exponent = min(retryCount, 6); // Cap 2^6 to prevent integer overflow
    final multiplier = pow(2, exponent).toInt();
    final delayMs = baseDelay.inMilliseconds * multiplier;
    final cappedMs = min(delayMs, maxDelay.inMilliseconds);
    return Duration(milliseconds: cappedMs);
  }

  /// Refreshes pending count and current status from SQLite.
  Future<void> refreshState() async {
    final pending = await outboxRepo.getPendingCount();
    final failedPermanent = await outboxRepo.getPermanentFailureCount();
    _state = _state.copyWith(
      pendingCount: pending,
      permanentFailureCount: failedPermanent,
    );
    notifyListeners();
  }

  /// Processes all pending outbox mutations in FIFO order.
  Future<SyncBatchResult> syncPendingMutations({DateTime? asOf}) async {
    if (_state.isSyncing) {
      return const SyncBatchResult(
        totalProcessed: 0,
        syncedCount: 0,
        transientErrorCount: 0,
        permanentErrorCount: 0,
      );
    }

    _state = _state.copyWith(isSyncing: true, lastError: null);
    notifyListeners();

    int totalProcessed = 0;
    int syncedCount = 0;
    int transientErrorCount = 0;
    int permanentErrorCount = 0;
    String? latestError;

    try {
      final mutations = await outboxRepo.getPendingMutations(asOf: asOf);

      for (final mutation in mutations) {
        totalProcessed++;
        await outboxRepo.markSyncing(mutation.id);

        try {
          final response = await gateway.submitOrderMutation(
            idempotencyKey: mutation.idempotencyKey,
            payloadJson: mutation.payloadJson,
          );

          if (response.isSuccess) {
            final srvId =
                response.serverOrderId ?? 'ACK-${mutation.clientOrderId}';
            await outboxRepo.markSynced(mutation.id, serverOrderId: srvId);
            syncedCount++;
          } else if (response.isPermanentError) {
            latestError = response.errorMessage;
            await outboxRepo.markPermanentFailure(
              mutation.id,
              error: response.errorMessage ?? 'Validation Error',
            );
            permanentErrorCount++;
          } else {
            // Transient error
            latestError = response.errorMessage;
            final backoff = calculateBackoff(mutation.retryCount);
            await outboxRepo.markTransientFailure(
              mutation.id,
              error: response.errorMessage ?? 'Transient Network Failure',
              backoff: backoff,
            );
            transientErrorCount++;
          }
        } catch (err) {
          // Uncaught network error treated as transient failure
          latestError = err.toString();
          final backoff = calculateBackoff(mutation.retryCount);
          await outboxRepo.markTransientFailure(
            mutation.id,
            error: err.toString(),
            backoff: backoff,
          );
          transientErrorCount++;
        }
      }
    } finally {
      final remainingPending = await outboxRepo.getPendingCount();
      final failedPermanent = await outboxRepo.getPermanentFailureCount();

      _state = _state.copyWith(
        isSyncing: false,
        pendingCount: remainingPending,
        permanentFailureCount: failedPermanent,
        lastError: latestError,
        lastSyncedAt: syncedCount > 0 ? DateTime.now() : _state.lastSyncedAt,
      );
      notifyListeners();
    }

    return SyncBatchResult(
      totalProcessed: totalProcessed,
      syncedCount: syncedCount,
      transientErrorCount: transientErrorCount,
      permanentErrorCount: permanentErrorCount,
    );
  }
}
