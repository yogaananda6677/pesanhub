import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/api_failure.dart';
import 'package:pesenhub_app/data/remote/contract_dto.dart';
import 'package:pesenhub_app/data/remote/order_dto.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';

const _fixturePath = '../contracts/backend_flutter_v1.json';
const _token = 'contract-test-token-at-least-32-characters';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() async {
    final file = File(_fixturePath);
    if (!file.existsSync()) {
      fail('Canonical contract fixture missing at $_fixturePath');
    }
    fixture = Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  });

  test('canonical enums match Flutter order, payment, and event consumers', () {
    final enums = Map<String, dynamic>.from(fixture['enums'] as Map);
    Set<String> values(String key) =>
        (enums[key] as List).cast<String>().toSet();

    expect(fixture['contract_version'], 1);
    expect(values('order_sources'), QueueOrderDto.validSources);
    expect(values('order_statuses'), QueueOrderDto.validStatuses);
    expect(values('payment_methods'), PaymentDto.validMethods);
    expect(values('payment_statuses'), PaymentDto.validStatuses);
    expect(values('event_types'), OrderEventDto.validTypes);
  });

  test(
    'queue and paginated order provider payload deserialize semantically',
    () async {
      final queueResponse = Map<String, dynamic>.from(
        fixture['queue_response'] as Map,
      );
      final client = PesenHubApiClient(
        config: ApiConfig(
          baseUri: Uri.parse('https://api.example.test/api/v1/'),
          token: _token,
        ),
        client: MockClient(
          (_) async => http.Response(jsonEncode(queueResponse), 200),
        ),
      );

      final queue = await client.fetchQueue();
      expect(queue, hasLength(1));
      expect(queue.single.source, 'CASHIER_MANUAL');
      expect(queue.single.orderStatus, 'PREPARING');
      expect(queue.single.version, 3);
      expect(queue.single.items.single.unitPrice, 25000);

      final collection = Map<String, dynamic>.from(
        fixture['order_collection'] as Map,
      );
      final page = PageMetaDto.fromJson(
        Map<String, dynamic>.from(collection['page'] as Map),
      );
      expect(page.size, 20);
      expect(page.nextCursor, isNotEmpty);
      final order = QueueOrderDto.fromJson(
        Map<String, dynamic>.from((collection['data'] as List).single as Map),
      ).order;
      expect(order.id, queue.single.id);
    },
  );

  test('payment and error envelopes remain strict and actionable', () async {
    final payment = PaymentDto.fromJson(
      Map<String, dynamic>.from(fixture['payment'] as Map),
    );
    expect(payment.method, 'MIDTRANS_QRIS');
    expect(payment.status, 'PAID');
    expect(payment.amount, 25000);

    const expectedKinds = {
      401: ApiFailureKind.unauthenticated,
      403: ApiFailureKind.forbidden,
      409: ApiFailureKind.conflict,
      422: ApiFailureKind.validation,
      500: ApiFailureKind.server,
    };
    for (final raw in fixture['error_cases'] as List) {
      final errorCase = Map<String, dynamic>.from(raw as Map);
      final status = errorCase['http_status'] as int;
      final body = Map<String, dynamic>.from(errorCase['body'] as Map);
      final headers = Map<String, String>.from(errorCase['headers'] as Map);
      final envelope = ErrorEnvelopeDto.fromJson(body);
      expect(envelope.requestId, headers['x-request-id']);
      expect(envelope.code, isNotEmpty);

      final client = PesenHubApiClient(
        config: ApiConfig(
          baseUri: Uri.parse('https://api.example.test/api/v1/'),
          token: _token,
        ),
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode(body), status, headers: headers),
        ),
      );
      try {
        await client.fetchQueue();
        fail('HTTP $status must fail');
      } on ApiFailure catch (failure) {
        expect(failure.kind, expectedKinds[status]);
        expect(failure.requestId, envelope.requestId);
      }
    }
  });

  test('event envelope version and payload stay correlated', () {
    for (final raw in fixture['events'] as List) {
      final json = Map<String, dynamic>.from(raw as Map);
      final event = OrderEventDto.fromJson(json);
      final payload = Map<String, dynamic>.from(json['payload'] as Map);
      expect(payload['order_id'], event.orderId);
      expect(payload['status'], event.status);
      expect(payload['version'], event.version);
    }
  });

  test('breaking rename and type changes fail the consumer contract', () {
    final queueResponse = Map<String, dynamic>.from(
      fixture['queue_response'] as Map,
    );
    final canonical = Map<String, dynamic>.from(
      (queueResponse['data'] as List).single as Map,
    );

    final renamed = _copy(canonical);
    renamed['origin'] = renamed.remove('source');
    expect(() => QueueOrderDto.fromJson(renamed), throwsFormatException);

    final wrongVersionType = _copy(canonical)..['version'] = '3';
    expect(
      () => QueueOrderDto.fromJson(wrongVersionType),
      throwsFormatException,
    );

    final wrongInteger = _copy(canonical)..['version'] = 3.5;
    expect(() => QueueOrderDto.fromJson(wrongInteger), throwsFormatException);

    final wrongPaymentType = _copy(
      Map<String, dynamic>.from(fixture['payment'] as Map),
    )..['amount'] = '25000';
    expect(() => PaymentDto.fromJson(wrongPaymentType), throwsFormatException);

    final event = _copy(
      Map<String, dynamic>.from((fixture['events'] as List).first as Map),
    )..remove('event_id');
    expect(() => OrderEventDto.fromJson(event), throwsFormatException);
  });
}
