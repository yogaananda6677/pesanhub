import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/session.dart';
import '../sync/sync_service.dart';
import '../../queue/models/queue_order.dart';
import 'api_config.dart';
import 'api_failure.dart';
import 'catalog_dto.dart';
import 'catalog_gateway.dart';
import 'order_dto.dart';
import '../../menu/models/menu_category.dart';
import '../../menu/models/menu_item.dart';

abstract class QueueRemoteGateway {
  Future<List<QueueOrder>> fetchQueue();
  Future<QueueOrder> fetchOrder(String id);
}

class PesenHubApiClient
    implements
        QueueRemoteGateway,
        OrderSyncGateway,
        AuthGateway,
        CatalogRemoteGateway {
  final ApiConfig config;
  final Future<String?> Function() accessToken;
  final http.Client _client;
  int _requestSequence = 0;

  PesenHubApiClient({
    required this.config,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<String> createGoogleChallenge() async {
    final response = await _send(
      'POST',
      config.resolve('auth/google/challenge'),
      authenticated: false,
    );
    try {
      final json = _decodeObject(response);
      final nonce = json['nonce'];
      if (nonce is! String || nonce.length < 32) throw const FormatException();
      return nonce;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  @override
  Future<SessionCredential> loginWithGoogle(
    String idToken,
    String nonce,
  ) async {
    final response = await _send(
      'POST',
      config.resolve('auth/google'),
      body: jsonEncode({'id_token': idToken, 'nonce': nonce}),
      authenticated: false,
    );
    try {
      return SessionCredential.fromJson(_decodeObject(response));
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  @override
  Future<AuthUser> currentUser() async {
    final response = await _send('GET', config.resolve('auth/me'));
    try {
      return AuthUser.fromJson(_decodeObject(response));
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  @override
  Future<void> logout() async {
    await _send('POST', config.resolve('auth/logout'));
  }

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
  Future<RemoteCatalog> fetchAdminCatalog() async {
    final response = await _send('GET', config.resolve('admin/catalog'));
    try {
      return decodeCatalog(_decodeObject(response));
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  @override
  Future<MenuCategory> createCategory(MenuCategory category) async {
    final response = await _send(
      'POST',
      config.resolve('admin/categories'),
      body: jsonEncode(encodeCategory(category)),
    );
    return _decodeCategoryResponse(response);
  }

  @override
  Future<MenuCategory> updateCategory(MenuCategory category) async {
    final id = Uri.encodeComponent(category.id);
    final response = await _send(
      'PATCH',
      config.resolve('admin/categories/$id'),
      body: jsonEncode(encodeCategory(category)),
    );
    return _decodeCategoryResponse(response);
  }

  @override
  Future<MenuItem> createMenu(MenuItem menu) async {
    final response = await _send(
      'POST',
      config.resolve('admin/menus'),
      body: jsonEncode(encodeMenu(menu)),
    );
    return _decodeMenuResponse(response);
  }

  @override
  Future<MenuItem> updateMenu(MenuItem menu) async {
    final id = Uri.encodeComponent(menu.id);
    final response = await _send(
      'PATCH',
      config.resolve('admin/menus/$id'),
      body: jsonEncode(encodeMenu(menu)),
    );
    return _decodeMenuResponse(response);
  }

  @override
  Future<MenuItem> updateMenuAvailability(
    String id,
    bool available,
    int expectedVersion,
  ) async {
    final safeId = Uri.encodeComponent(id);
    final response = await _send(
      'PATCH',
      config.resolve('admin/menus/$safeId/availability'),
      body: jsonEncode({'is_available': available, 'version': expectedVersion}),
    );
    return _decodeMenuResponse(response);
  }

  MenuCategory _decodeCategoryResponse(http.Response response) {
    try {
      return decodeCategory(_decodeObject(response));
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  MenuItem _decodeMenuResponse(http.Response response) {
    try {
      return decodeMenu(_decodeObject(response));
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
    bool authenticated = true,
  }) async {
    final requestId = _nextRequestId();
    try {
      final token = authenticated ? await accessToken() : null;
      if (authenticated && (token == null || token.isEmpty)) {
        throw ApiFailure(ApiFailureKind.unauthenticated, requestId: requestId);
      }
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
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
