import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesenhub_app/auth/login_view.dart';
import 'package:pesenhub_app/auth/session.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/api_failure.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';

class _Gateway implements AuthGateway {
  Object? result;
  String? username;
  String? password;

  _Gateway(this.result);

  @override
  Future<SessionCredential> login(String username, String password) async {
    this.username = username;
    this.password = password;
    final value = result;
    if (value is Exception) throw value;
    return value! as SessionCredential;
  }
}

SessionCredential credential({DateTime? expiresAt}) => SessionCredential(
  accessToken: 'session-token',
  expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
);

void main() {
  test('restores valid session and removes expired session', () async {
    final validStore = MemorySessionStore(credential());
    final valid = SessionController(
      store: validStore,
      gateway: _Gateway(credential()),
    );
    await valid.restore();
    expect(valid.status, SessionStatus.signedIn);
    expect(await valid.accessToken(), 'session-token');

    final expiredStore = MemorySessionStore(
      credential(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      ),
    );
    final expired = SessionController(
      store: expiredStore,
      gateway: _Gateway(credential()),
    );
    await expired.restore();
    expect(await expired.accessToken(), isNull);
    expect(expired.status, SessionStatus.signedOut);
    expect(expiredStore.credential, isNull);
  });

  test('sign in persists session and sign out removes it', () async {
    final store = MemorySessionStore();
    final gateway = _Gateway(credential());
    final controller = SessionController(store: store, gateway: gateway);
    await controller.restore();

    expect(await controller.signIn(' outlet ', 'secret'), isTrue);
    expect(gateway.username, 'outlet');
    expect(gateway.password, 'secret');
    expect(store.credential, isNotNull);
    expect(controller.status, SessionStatus.signedIn);

    await controller.signOut();
    expect(store.credential, isNull);
    expect(controller.status, SessionStatus.signedOut);
  });

  test('active session signs out automatically at expiry', () async {
    final store = MemorySessionStore(
      credential(
        expiresAt: DateTime.now().toUtc().add(const Duration(milliseconds: 20)),
      ),
    );
    final controller = SessionController(
      store: store,
      gateway: _Gateway(credential()),
    );
    await controller.restore();
    expect(controller.status, SessionStatus.signedIn);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(controller.status, SessionStatus.signedOut);
    expect(store.credential, isNull);
  });

  test('API login is unauthenticated and decodes session contract', () async {
    late http.Request captured;
    final client = PesenHubApiClient(
      config: ApiConfig(baseUri: Uri.parse('https://api.example.test/api/v1/')),
      accessToken: () async => null,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'access_token': 'signed-session-token',
            'token_type': 'Bearer',
            'expires_at': '2026-09-06T16:00:00Z',
          }),
          200,
        );
      }),
    );

    final result = await client.login('outlet', 'secret');
    expect(result.accessToken, 'signed-session-token');
    expect(captured.url.path, '/api/v1/auth/login');
    expect(captured.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(captured.body), {
      'username': 'outlet',
      'password': 'secret',
    });
  });

  testWidgets('login UI has no owner or operator persona selector', (
    tester,
  ) async {
    final gateway = _Gateway(const ApiFailure(ApiFailureKind.unauthenticated));
    final controller = SessionController(
      store: MemorySessionStore(),
      gateway: gateway,
    );
    await controller.restore();
    await tester.pumpWidget(
      MaterialApp(home: LoginView(controller: controller)),
    );

    expect(find.text('Masuk ke PesenHub'), findsOneWidget);
    expect(find.textContaining('Owner'), findsNothing);
    expect(find.textContaining('Operator'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), 'outlet');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Username atau kata sandi salah.'), findsOneWidget);
  });
}
