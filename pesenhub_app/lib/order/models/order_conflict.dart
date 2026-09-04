import '../../queue/models/queue_order.dart';

/// Categorization of order state conflicts between local device and server.
/// Fulfills Issue #34 Acceptance Criteria #1 and #3.
enum ConflictType {
  /// Server is in a terminal lifecycle state (COMPLETED, CANCELLED, REJECTED).
  /// Unsafe to overwrite.
  unsafeFinalState,

  /// Server payment status has progressed to PAID.
  /// Unsafe to overwrite or revert.
  unsafePaymentMismatch,

  /// Server version has advanced with different lifecycle status.
  /// Unsafe to overwrite.
  unsafeVersionDrift,

  /// Lifecycle status and payment are compatible, but safe non-lifecycle
  /// fields (e.g. takeawayNotes) differ between client and server.
  /// Safe for user resolution.
  safeEditableField,
}

/// Available resolution strategies for conflicts.
enum ResolutionStrategy {
  /// Discard local changes and adopt server data.
  serverWins,

  /// Keep local changes (only permitted for safe editable fields).
  clientWins,

  /// Merge conflicting fields (e.g. concatenating notes).
  merge,

  /// Unsafe conflict requiring full reload from server.
  forceReload,
}

/// Structured outcome of conflict analysis.
class ConflictClassification {
  final ConflictType type;
  final bool isSafe;
  final String reason;
  final ResolutionStrategy defaultStrategy;
  final List<ResolutionStrategy> allowedStrategies;
  final QueueOrder localOrder;
  final QueueOrder serverOrder;

  const ConflictClassification({
    required this.type,
    required this.isSafe,
    required this.reason,
    required this.defaultStrategy,
    required this.allowedStrategies,
    required this.localOrder,
    required this.serverOrder,
  });

  /// True if server state must take precedence without local override.
  bool get enforcesServerWins => !isSafe;
}

/// Evaluates differences between local and server orders and classifies conflict safety.
class ConflictClassifier {
  static const _finalStatuses = {'COMPLETED', 'CANCELLED', 'REJECTED'};

  /// Evaluates two versions of an order and classifies the conflict.
  static ConflictClassification classify({
    required QueueOrder localOrder,
    required QueueOrder serverOrder,
  }) {
    // 1. Unsafe: Server is in terminal/final state
    if (_finalStatuses.contains(serverOrder.orderStatus) &&
        localOrder.orderStatus != serverOrder.orderStatus) {
      return ConflictClassification(
        type: ConflictType.unsafeFinalState,
        isSafe: false,
        reason:
            'Pesanan telah berstatus final (${serverOrder.orderStatus}) di server. '
            'Perubahan lokal tidak dapat menimpa status ini.',
        defaultStrategy: ResolutionStrategy.serverWins,
        allowedStrategies: const [
          ResolutionStrategy.serverWins,
          ResolutionStrategy.forceReload,
        ],
        localOrder: localOrder,
        serverOrder: serverOrder,
      );
    }

    // 2. Unsafe: Payment state mismatch (Server is PAID, client is not)
    if (serverOrder.paymentStatus == 'PAID' &&
        localOrder.paymentStatus != 'PAID') {
      return ConflictClassification(
        type: ConflictType.unsafePaymentMismatch,
        isSafe: false,
        reason:
            'Pembayaran pesanan telah dikonfirmasi (PAID) di server. '
            'Status pembayaran server wajib dipertahankan.',
        defaultStrategy: ResolutionStrategy.serverWins,
        allowedStrategies: const [
          ResolutionStrategy.serverWins,
          ResolutionStrategy.forceReload,
        ],
        localOrder: localOrder,
        serverOrder: serverOrder,
      );
    }

    // 3. Unsafe: Version drift with different lifecycle status
    if (serverOrder.version > localOrder.version &&
        serverOrder.orderStatus != localOrder.orderStatus) {
      return ConflictClassification(
        type: ConflictType.unsafeVersionDrift,
        isSafe: false,
        reason:
            'Status pesanan telah diubah oleh perangkat lain menjadi '
            '${serverOrder.orderStatus} (versi server: ${serverOrder.version}, lokal: ${localOrder.version}).',
        defaultStrategy: ResolutionStrategy.serverWins,
        allowedStrategies: const [
          ResolutionStrategy.serverWins,
          ResolutionStrategy.forceReload,
        ],
        localOrder: localOrder,
        serverOrder: serverOrder,
      );
    }

    // 4. Safe: Lifecycle status is identical, but safe fields differ (e.g. notes)
    final localNotes = (localOrder.takeawayNotes ?? '').trim();
    final serverNotes = (serverOrder.takeawayNotes ?? '').trim();
    final notesDiffer = localNotes != serverNotes;

    if (notesDiffer || localOrder.isTakeaway != serverOrder.isTakeaway) {
      return ConflictClassification(
        type: ConflictType.safeEditableField,
        isSafe: true,
        reason:
            'Catatan atau preferensi layanan pesanan berbeda antara lokal dan server.',
        defaultStrategy: ResolutionStrategy.clientWins,
        allowedStrategies: const [
          ResolutionStrategy.clientWins,
          ResolutionStrategy.serverWins,
          ResolutionStrategy.merge,
        ],
        localOrder: localOrder,
        serverOrder: serverOrder,
      );
    }

    // Default safe fallback if versions drift without functional conflict
    return ConflictClassification(
      type: ConflictType.safeEditableField,
      isSafe: true,
      reason: 'Data lokal dan server memiliki perbedaan versi minor yang aman.',
      defaultStrategy: ResolutionStrategy.serverWins,
      allowedStrategies: const [
        ResolutionStrategy.serverWins,
        ResolutionStrategy.clientWins,
      ],
      localOrder: localOrder,
      serverOrder: serverOrder,
    );
  }
}

/// Applies a resolution strategy deterministically to produce the resolved order.
class ConflictResolver {
  /// Resolves the conflict based on the chosen strategy.
  static QueueOrder resolve({
    required ConflictClassification classification,
    required ResolutionStrategy strategy,
  }) {
    final local = classification.localOrder;
    final server = classification.serverOrder;

    switch (strategy) {
      case ResolutionStrategy.serverWins:
      case ResolutionStrategy.forceReload:
        return server;

      case ResolutionStrategy.clientWins:
        if (!classification.isSafe) {
          // Safeguard: Unsafe conflicts CANNOT use clientWins
          return server;
        }
        return local.copyWith(
          // Ensure version increments past server to prevent continuous conflict
          version: (server.version >= local.version)
              ? server.version + 1
              : local.version + 1,
        );

      case ResolutionStrategy.merge:
        if (!classification.isSafe) {
          return server;
        }
        final localNotes = (local.takeawayNotes ?? '').trim();
        final serverNotes = (server.takeawayNotes ?? '').trim();

        String mergedNotes;
        if (localNotes.isEmpty) {
          mergedNotes = serverNotes;
        } else if (serverNotes.isEmpty || localNotes == serverNotes) {
          mergedNotes = localNotes;
        } else {
          mergedNotes = '$serverNotes | [Lokal: $localNotes]';
        }

        return server.copyWith(
          takeawayNotes: mergedNotes,
          isTakeaway: local.isTakeaway || server.isTakeaway,
          version: (server.version >= local.version)
              ? server.version + 1
              : local.version + 1,
        );
    }
  }
}
