import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sync/sync_service.dart';
import '../../queue/models/queue_order.dart';
import 'api_config.dart';
import 'api_failure.dart';
import 'order_dto.dart';

abstract class QueueRemoteGateway {
  Future<List<QueueOrder>> fetchQueue();
  Future<QueueOrder> fetchOrder(String id);
}

class PesenHubApiClient implements QueueRemoteGateway, OrderSyncGateway {
  final ApiConfig config;
  final http.Client _client;
  int _requestSequence = 0;

  PesenHubApiClient({required this.config, http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<List<QueueOrder>> fetchQueue() async {
    final response = await _send('GET', config.resolve('orders/queue'));
    final json = _decodeObject(response);
    final data = json['data'];
    if (data is! List) throw _invalidResponse(response);
    try {
      return data
          .map(
            (value) => QueueOrderDto.fromJson(
              Map<String, dynamic>.from(value as Map),
            ).order,
          )
          .toList(growable: false);
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  @override
  Future<QueueOrder> fetchOrder(String id) async {
    final safeId = Uri.encodeComponent(id);
    final response = await _send('GET', config.resolve('orders/$safeId'));
    try {
      return QueueOrderDto.fromJson(_decodeObject(response)).order;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  @override
  Future<SyncGatewayResponse> submitOrderMutation({
    required String idempotencyKey,
    required String payloadJson,
  }) async {
    try {
      final raw = jsonDecode(payloadJson);
      if (raw is! Map) throw const FormatException('invalid mutation');
      final payload = _normalizeManualOrder(Map<String, dynamic>.from(raw));
      final response = await _send(
        'POST',
        config.resolve('orders'),
        body: jsonEncode(payload),
        extraHeaders: {'Idempotency-Key': idempotencyKey},
      );
      final json = _decodeObject(response);
      final id = json['id'];
      if (id is! String || id.isEmpty) throw _invalidResponse(response);
      return SyncGatewayResponse.success(serverOrderId: id);
    } on ApiFailure catch (failure) {
      final kind = _syncFailureKind(failure.kind);
      if (failure.isTransient) {
        return SyncGatewayResponse.transientError(
          errorMessage: failure.presentationMessage,
          failureKind: kind,
        );
      }
      return SyncGatewayResponse.permanentError(
        errorMessage: failure.presentationMessage,
        failureKind: kind,
      );
    } catch (_) {
      return const SyncGatewayResponse.permanentError(
        errorMessage: 'Payload outbox tidak sesuai kontrak server.',
        failureKind: SyncFailureKind.validation,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    String? body,
    Map<String, String> extraHeaders = const {},
  }) async {
    final requestId = _nextRequestId();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Accept': 'application/json',
          'Authorization': 'Bearer ${config.token}',
          'X-Request-ID': requestId,
          if (body != null) 'Content-Type': 'application/json',
          ...extraHeaders,
        });
      if (body != null) request.body = body;
      final streamed = await _client
          .send(request)
          .timeout(config.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      throw _failureForStatus(response, requestId);
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw ApiFailure(ApiFailureKind.network, requestId: requestId);
    } catch (_) {
      throw ApiFailure(ApiFailureKind.network, requestId: requestId);
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    throw _invalidResponse(response);
  }

  ApiFailure _failureForStatus(http.Response response, String fallbackId) {
    final requestId = response.headers['x-request-id'] ?? fallbackId;
    switch (response.statusCode) {
      case 401:
        return ApiFailure(
          ApiFailureKind.unauthenticated,
          statusCode: response.statusCode,
          requestId: requestId,
        );
      case 403:
        return ApiFailure(
          ApiFailureKind.forbidden,
          statusCode: response.statusCode,
          requestId: requestId,
        );
      case 409:
        return ApiFailure(
          ApiFailureKind.conflict,
          statusCode: response.statusCode,
          requestId: requestId,
        );
      case 400:
      case 422:
        return ApiFailure(
          ApiFailureKind.validation,
          statusCode: response.statusCode,
          requestId: requestId,
        );
      default:
        return ApiFailure(
          response.statusCode >= 500
              ? ApiFailureKind.server
              : ApiFailureKind.invalidResponse,
          statusCode: response.statusCode,
          requestId: requestId,
        );
    }
  }

  ApiFailure _invalidResponse(http.Response response) => ApiFailure(
    ApiFailureKind.invalidResponse,
    statusCode: response.statusCode,
    requestId: response.headers['x-request-id'],
  );

  String _nextRequestId() {
    _requestSequence++;
    return 'mobile-${DateTime.now().microsecondsSinceEpoch}-$_requestSequence';
  }

  static Map<String, dynamic> _normalizeManualOrder(
    Map<String, dynamic> source,
  ) {
    final rawItems = source['items'];
    if (rawItems is! List) throw const FormatException('items are required');
    return {
      'client_order_id': source['client_order_id'],
      'customer_name': source['customer_name'],
      if (source['customer_phone'] is String &&
          !(source['customer_phone'] as String).contains('*'))
        'customer_phone': source['customer_phone'],
      if (source['takeaway_notes'] is String) 'notes': source['takeaway_notes'],
      'items': rawItems
          .map((raw) {
            final item = Map<String, dynamic>.from(raw as Map);
            return {
              'menu_id': item['menu_id'],
              'quantity': item['quantity'],
              if (item['notes'] is String &&
                  (item['notes'] as String).isNotEmpty)
                'notes': item['notes'],
              if (item['modifier_groups'] is List)
                'modifier_groups': item['modifier_groups'],
            };
          })
          .toList(growable: false),
    };
  }

  static SyncFailureKind _syncFailureKind(ApiFailureKind kind) {
    return SyncFailureKind.values.byName(kind.name);
  }

  void close() => _client.close();
}
