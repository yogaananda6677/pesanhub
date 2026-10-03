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
import '../../settings/models/employee.dart';

abstract class QueueRemoteGateway {
  Future<List<QueueOrder>> fetchQueue();
  Future<QueueOrder> fetchOrder(String id);
  Future<QueueOrder> transitionOrderStatus(
    String orderId,
    String targetStatus,
    int expectedVersion, {
    String? reasonCode,
  }) {
    throw UnimplementedError();
  }
}

class PesenHubApiClient
    implements
        QueueRemoteGateway,
        OrderSyncGateway,
        AuthGateway,
        CatalogRemoteGateway {
  final ApiConfig config;
  final Future<String?> Function() accessToken;
  final Future<String?> Function()? activeBranchId;
  final http.Client _client;
  int _requestSequence = 0;

  PesenHubApiClient({
    required this.config,
    required this.accessToken,
    this.activeBranchId,
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
  Future<SessionCredential> loginWithPassword(
    String username,
    String password,
  ) async {
    final response = await _send(
      'POST',
      config.resolve('auth/login'),
      body: jsonEncode({'username': username.trim(), 'password': password}),
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

  Future<String> inviteCashier(String email) async {
    final response = await _send(
      'POST',
      config.resolve('admin/cashiers/invitations'),
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );
    try {
      final json = _decodeObject(response);
      final maskedEmail = json['email'];
      final role = json['role'];
      final status = json['status'];
      if (maskedEmail is! String || role != 'CASHIER' || status != 'PENDING') {
        throw const FormatException('invalid invitation response');
      }
      return maskedEmail;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  Future<Map<String, dynamic>> updateMyDisplayName(String newName) async {
    final response = await _send(
      'PATCH',
      config.resolve('auth/me'),
      body: jsonEncode({'display_name': newName.trim()}),
    );
    try {
      return _decodeObject(response);
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  Future<List<Employee>> fetchEmployees({String? search}) async {
    final baseUri = config.resolve('admin/employees');
    final uri = (search != null && search.trim().isNotEmpty)
        ? baseUri.replace(queryParameters: {'q': search.trim()})
        : baseUri;
    final response = await _send('GET', uri);
    final json = _decodeObject(response);
    final data = json['data'];
    if (data is! List) throw _invalidResponse(response);
    try {
      return data
          .map(
            (item) => Employee.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  Future<Employee> createEmployee({
    required String displayName,
    required String email,
    required String role,
    String? branchId,
    String? password,
  }) async {
    final response = await _send(
      'POST',
      config.resolve('admin/employees'),
      body: jsonEncode({
        'display_name': displayName.trim(),
        'email': email.trim().toLowerCase(),
        'role': role,
        if (branchId != null && branchId.isNotEmpty) 'branch_id': branchId,
        if (password != null && password.isNotEmpty) 'password': password,
      }),
    );
    try {
      final json = _decodeObject(response);
      return Employee.fromJson(json);
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  Future<Employee> updateEmployee(
    String id, {
    String? displayName,
    String? role,
    String? status,
    String? branchId,
  }) async {
    final response = await _send(
      'PATCH',
      config.resolve('admin/employees/$id'),
      body: jsonEncode({
        if (displayName != null) 'display_name': displayName.trim(),
        'role': ?role,
        'status': ?status,
        'branch_id': ?branchId,
      }),
    );
    try {
      final json = _decodeObject(response);
      return Employee.fromJson(json);
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw _invalidResponse(response);
    }
  }

  Future<void> deleteEmployee(String id) async {
    await _send('DELETE', config.resolve('admin/employees/$id'));
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
    final rawId = id.startsWith('ord-') ? id.substring(4) : id;
    final safeId = Uri.encodeComponent(rawId);
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
  Future<QueueOrder> transitionOrderStatus(
    String orderId,
    String targetStatus,
    int expectedVersion, {
    String? reasonCode,
  }) async {
    final rawId = orderId.startsWith('ord-') ? orderId.substring(4) : orderId;
    final safeId = Uri.encodeComponent(rawId);
    final bodyMap = <String, dynamic>{
      'target_status': targetStatus,
      'expected_version': expectedVersion,
    };
    if (reasonCode != null && reasonCode.isNotEmpty) {
      bodyMap['reason_code'] = reasonCode;
    }
    final response = await _send(
      'POST',
      config.resolve('orders/$safeId/status-transitions'),
      body: jsonEncode(bodyMap),
      extraHeaders: {
        'Idempotency-Key':
            'trans-$orderId-$expectedVersion-${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    final json = _decodeObject(response);
    final newStatus = json['status'] as String? ?? targetStatus;
    final newVersion =
        (json['version'] as num?)?.toInt() ?? (expectedVersion + 1);

    try {
      return await fetchOrder(orderId);
    } catch (_) {
      return QueueOrder(
        id: orderId,
        orderNumber: '',
        customerName: '',
        customerPhone: '',
        source: '',
        orderStatus: newStatus,
        paymentStatus: '',
        createdAt: DateTime.now(),
        version: newVersion,
      );
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
  Future<RemoteCatalog> fetchPublicCatalog() async {
    final response = await _send(
      'GET',
      config.resolve('public/menu'),
      authenticated: false,
    );
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

  Future<String> uploadMenuImage(String filename, List<int> bytes) async {
    final request = http.MultipartRequest(
      'POST',
      config.resolve('admin/menu-images'),
    );
    final token = await accessToken();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final requestId = _nextRequestId();
    request.headers['X-Request-ID'] = requestId;
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: filename),
    );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failureForStatus(response, requestId);
    }
    final imageUrl = _decodeObject(response)['image_url'];
    if (imageUrl is! String || imageUrl.isEmpty) {
      throw _invalidResponse(response);
    }
    return imageUrl;
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
      final map = Map<String, dynamic>.from(raw);
      if (map.containsKey('target_status') && map.containsKey('order_id')) {
        final orderId = map['order_id'] as String;
        final targetStatus = map['target_status'] as String;
        final expectedVersion = (map['expected_version'] as num?)?.toInt() ?? 1;
        final reasonCode = map['reason_code'] as String?;
        await transitionOrderStatus(
          orderId,
          targetStatus,
          expectedVersion,
          reasonCode: reasonCode,
        );
        return SyncGatewayResponse.success(serverOrderId: orderId);
      }
      final payload = _normalizeManualOrder(map);
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
      final branchId = activeBranchId != null ? await activeBranchId!() : null;
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Request-ID': requestId,
          if (branchId != null && branchId.isNotEmpty) 'X-Branch-ID': branchId,
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
      if (source['branch_id'] is String &&
          (source['branch_id'] as String).isNotEmpty)
        'branch_id': source['branch_id'],
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

  Future<Map<String, dynamic>> fetchReportSummary({
    String? branchId,
    DateTime? from,
    DateTime? to,
    bool includeBranches = false,
  }) async {
    final queryParams = <String, String>{
      if (branchId != null && branchId.isNotEmpty) 'branch_id': branchId,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (includeBranches) 'include_branches': 'true',
    };
    final uri = config
        .resolve('reports/summary')
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await _send('GET', uri);
    final json = _decodeObject(response);
    return Map<String, dynamic>.from(json['summary'] as Map);
  }

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    final response = await _send('GET', config.resolve('branches'));
    final json = _decodeObject(response);
    final rawList = json['branches'];
    if (rawList is List) {
      return rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  void close() => _client.close();
}
