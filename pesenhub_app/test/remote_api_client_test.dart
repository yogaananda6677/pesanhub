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
  ApiConfig config() => ApiConfig(
    baseUri: Uri.parse('https://api.example.test/api/v1'),
    token: _token,
  );

  test(
    'config normalizes REST URL and derives authenticated WebSocket URL',
    () {
      final value = config();

      expect(
        value.resolve('orders/queue').toString(),
        'https://api.example.test/api/v1/orders/queue',
      );
      expect(value.websocketUri().scheme, 'wss');
      expect(value.websocketUri().queryParameters['token'], _token);
      expect(
        () => ApiConfig(
          baseUri: Uri.parse('http://api.example.test/api/v1'),
          token: _token,
        ),
        throwsFormatException,
      );
    },
  );

  test('queue snapshot maps DTO and sends auth plus correlation ID', () async {
    late http.Request captured;
    final client = PesenHubApiClient(
      config: config(),
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
    'outbox mutation is reduced to backend allowlist and remains idempotent',
    () async {
      late http.Request captured;
      final client = PesenHubApiClient(
        config: config(),
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
}
