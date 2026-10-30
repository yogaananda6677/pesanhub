import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/api_failure.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/data/sync/sync_service.dart';

const _token = 'mobile-test-token-at-least-32-characters';

Map<String, dynamic> _orderJson({int version = 1}) => {
  'id': 'order-1',
  'order_number': 'ORD-001',
  'source': 'CASHIER_MANUAL',
  'status': 'PENDING',
  'customer_name': 'Pelanggan Uji',
  'customer_phone': '0812****7890',
  'notes': 'Tanpa sedotan',
  'version': version,
  'created_at': '2026-09-05T08:00:00Z',
  'items': [
    {
      'name': 'Es Teh',
      'category_name': 'Minuman',
      'quantity': 2,
      'unit_price_amount': 5000,
    },
  ],
};

void main() {
  ApiConfig config() =>
      ApiConfig(baseUri: Uri.parse('https://api.example.test/api/v1'));

  Future<String?> accessToken() async => _token;

  test(
    'config normalizes REST URL and derives authenticated WebSocket URL',
    () {
      final value = config();

      expect(
        value.resolve('orders/queue').toString(),
        'https://api.example.test/api/v1/orders/queue',
      );
      expect(value.websocketUri(_token).scheme, 'wss');
      expect(value.websocketUri(_token).queryParameters['token'], _token);
      expect(
        () => ApiConfig(baseUri: Uri.parse('http://api.example.test/api/v1')),
        throwsFormatException,
      );
      expect(
        ApiConfig(
          baseUri: Uri.parse('http://192.168.1.11:8080/api/v1'),
        ).baseUri.toString(),
        'http://192.168.1.11:8080/api/v1/',
      );
      expect(
        ApiConfig(
          baseUri: Uri.parse('http://10.0.2.2:8080/api/v1/'),
        ).baseUri.toString(),
        'http://10.0.2.2:8080/api/v1/',
      );
    },
  );

  test('queue snapshot maps DTO and sends auth plus correlation ID', () async {
    late http.Request captured;
    final client = PesenHubApiClient(
      config: config(),
      accessToken: accessToken,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [_orderJson()],
          }),
          200,
        );
      }),
    );

    final orders = await client.fetchQueue();

    expect(orders, hasLength(1));
    expect(orders.single.customerPhone, '0812****7890');
    expect(orders.single.items.single.isDrink, isTrue);
    expect(captured.headers['Authorization'], 'Bearer $_token');
    expect(captured.headers['X-Request-ID'], startsWith('mobile-'));
  });

  test('HTTP failures map to distinct safe UI states', () async {
    const cases = {
      401: ApiFailureKind.unauthenticated,
      403: ApiFailureKind.forbidden,
      422: ApiFailureKind.validation,
      409: ApiFailureKind.conflict,
      500: ApiFailureKind.server,
    };

    final messages = <String>{};
    for (final entry in cases.entries) {
      final client = PesenHubApiClient(
        config: config(),
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response(
            'sensitive-provider-body',
            entry.key,
            headers: {'x-request-id': 'req-${entry.key}'},
          ),
        ),
      );

      try {
        await client.fetchQueue();
        fail('status ${entry.key} should fail');
      } on ApiFailure catch (failure) {
        expect(failure.kind, entry.value);
        expect(failure.requestId, 'req-${entry.key}');
        expect(failure.presentationMessage, isNotEmpty);
        messages.add(failure.presentationMessage);
        expect(failure.toString(), isNot(contains(_token)));
        expect(failure.toString(), isNot(contains('sensitive-provider-body')));
      }
    }
    expect(messages, hasLength(cases.length));
  });

  test(
    'cashier invitation sends only normalized email and trusts backend role',
    () async {
      late http.Request captured;
      final client = PesenHubApiClient(
        config: config(),
        accessToken: accessToken,
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'id': 'invite-1',
              'email': 'ca***@example.com',
              'role': 'CASHIER',
              'status': 'PENDING',
            }),
            201,
          );
        }),
      );

      final masked = await client.inviteCashier('  Cashier@Example.com  ');
      expect(masked, 'ca***@example.com');
      expect(captured.url.path, '/api/v1/admin/cashiers/invitations');
      expect(jsonDecode(captured.body), {'email': 'cashier@example.com'});
      expect(captured.body, isNot(contains('role')));
    },
  );

  test(
    'outbox mutation is reduced to backend allowlist and remains idempotent',
    () async {
      late http.Request captured;
      final client = PesenHubApiClient(
        config: config(),
        accessToken: accessToken,
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'id': 'server-order-1'}), 201);
        }),
      );

      final result = await client.submitOrderMutation(
        idempotencyKey: 'idem-1',
        payloadJson: jsonEncode({
          'client_order_id': 'client-1',
          'customer_name': 'Pelanggan Uji',
          'customer_phone': '0812****7890',
          'local_only': 'must-not-leave-device',
          'items': [
            {
              'menu_id': 'menu-1',
              'quantity': 1,
              'unit_price': 999,
              'modifier_groups': [
                {
                  'group_id': 'group-1',
                  'option_ids': ['option-1'],
                },
              ],
            },
          ],
        }),
      );

      expect(result.isSuccess, isTrue);
      expect(captured.headers['Idempotency-Key'], 'idem-1');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent.containsKey('local_only'), isFalse);
      expect(sent.containsKey('customer_phone'), isFalse);
      expect((sent['items'] as List).single, isNot(contains('unit_price')));
    },
  );

  test('outbox maps server and validation failures to retry policy', () async {
    Future<SyncGatewayResponse> submit(int status) {
      final client = PesenHubApiClient(
        config: config(),
        accessToken: accessToken,
        client: MockClient((_) async => http.Response('{}', status)),
      );
      return client.submitOrderMutation(
        idempotencyKey: 'idem',
        payloadJson:
            '{"client_order_id":"client","customer_name":"Uji","items":[]}',
      );
    }

    final validation = await submit(422);
    final server = await submit(503);
    expect(validation.isPermanentError, isTrue);
    expect(validation.failureKind, SyncFailureKind.validation);
    expect(server.isPermanentError, isFalse);
    expect(server.failureKind, SyncFailureKind.server);
  });

  test('fetchBranches parses both data and branches root keys', () async {
    final client1 = PesenHubApiClient(
      config: config(),
      accessToken: accessToken,
      client: MockClient((req) async {
        expect(req.url.path, '/api/v1/branches');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'b1',
                'name': 'Cabang Utama',
                'is_open': true,
                'open_time': '16:00',
                'close_time': '23:30',
              },
            ],
          }),
          200,
        );
      }),
    );
    final branches1 = await client1.fetchBranches();
    expect(branches1.length, 1);
    expect(branches1.first['name'], 'Cabang Utama');
    expect(branches1.first['open_time'], '16:00');

    final client2 = PesenHubApiClient(
      config: config(),
      accessToken: accessToken,
      client: MockClient((req) async {
        return http.Response(
          jsonEncode({
            'branches': [
              {'id': 'b2', 'name': 'Cabang Rogojampi'},
            ],
          }),
          200,
        );
      }),
    );
    final branches2 = await client2.fetchBranches();
    expect(branches2.length, 1);
    expect(branches2.first['id'], 'b2');
  });

  test(
    'fetchBranch and updateBranchOperational call correct endpoints with payload',
    () async {
      http.Request? capturedPatch;
      final client = PesenHubApiClient(
        config: config(),
        accessToken: accessToken,
        client: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/api/v1/branches/b-01') {
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 'b-01',
                  'name': 'Cabang Banyuwangi',
                  'open_time': '16:00',
                  'close_time': '23:30',
                  'open_days': 'SENIN,SELASA,RABU,KAMIS,JUMAT,SABTU,MINGGU',
                  'is_open': true,
                },
              }),
              200,
            );
          }
          if (req.method == 'PATCH' &&
              req.url.path == '/api/v1/branches/b-01/operational') {
            capturedPatch = req;
            return http.Response(
              jsonEncode({
                'message': 'updated',
                'branch': {
                  'id': 'b-01',
                  'open_time': '17:00',
                  'close_time': '23:00',
                  'is_open': false,
                },
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final branch = await client.fetchBranch('b-01');
      expect(branch, isNotNull);
      expect(branch!['name'], 'Cabang Banyuwangi');
      expect(branch['is_open'], isTrue);

      final updateRes = await client.updateBranchOperational(
        'b-01',
        openTime: '17:00',
        closeTime: '23:00',
        isOpen: false,
      );
      expect(updateRes['message'], 'updated');
      expect(capturedPatch, isNotNull);
      final body = jsonDecode(capturedPatch!.body) as Map<String, dynamic>;
      expect(body['open_time'], '17:00');
      expect(body['close_time'], '23:00');
      expect(body['is_open'], isFalse);
    },
  );
}
