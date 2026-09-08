import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesenhub_app/auth/approval_locked_view.dart';
import 'package:pesenhub_app/auth/google_identity_client.dart';
import 'package:pesenhub_app/auth/login_view.dart';
import 'package:pesenhub_app/auth/session.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/api_failure.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';

const approvedUser = AuthUser(
  id: 'user-1',
  email: 'ow***@example.test',
  displayName: 'Owner',
  role: 'OWNER',
  status: ApprovalStatus.approved,
);

class _Gateway implements AuthGateway {
  SessionCredential result;
  AuthUser current;
  Object? loginError;
  Object? currentError;
  bool loggedOut = false;

  _Gateway(
    this.result, {
    this.current = approvedUser,
    this.loginError,
    this.currentError,
  });

  @override
  Future<String> createGoogleChallenge() async => List.filled(43, 'n').join();

  @override
  Future<SessionCredential> loginWithGoogle(
    String idToken,
    String nonce,
  ) async {
    if (loginError != null) throw loginError!;
    return result;
  }

  @override
  Future<AuthUser> currentUser() async {
    if (currentError != null) throw currentError!;
    return current;
  }

  @override
  Future<void> logout() async => loggedOut = true;
}

class _Identity implements GoogleIdentityClient {
  bool signedOut = false;

  @override
  Future<String> authenticate(String nonce) async => 'google-id-token';

  @override
  Future<void> signOut() async => signedOut = true;
}

SessionCredential credential({
  DateTime? expiresAt,
  AuthUser user = approvedUser,
}) => SessionCredential(
  accessToken: 'session-token',
  expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
  user: user,
);

void main() {
  test('restore revalidates approval and removes expired session', () async {
    final validStore = MemorySessionStore(credential());
    final valid = SessionController(
      store: validStore,
      gateway: _Gateway(credential()),
      identityClient: _Identity(),
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
      identityClient: _Identity(),
    );
    await expired.restore();
    expect(expired.status, SessionStatus.signedOut);
    expect(expiredStore.credential, isNull);
  });

  test(
    'Google sign in persists pending session without unlocking app',
    () async {
      const pending = AuthUser(
        id: 'user-2',
        email: 'pe***@example.test',
        displayName: 'Pending Owner',
        role: 'OWNER',
        status: ApprovalStatus.pending,
      );
      final store = MemorySessionStore();
      final gateway = _Gateway(credential(user: pending), current: pending);
      final identity = _Identity();
      final controller = SessionController(
        store: store,
        gateway: gateway,
        identityClient: identity,
      );
      await controller.restore();

      expect(await controller.signInWithGoogle(), isTrue);
      expect(store.credential, isNotNull);
      expect(controller.status, SessionStatus.pendingApproval);

      await controller.signOut();
      expect(gateway.loggedOut, isTrue);
      expect(identity.signedOut, isTrue);
      expect(store.credential, isNull);
    },
  );

  test(
    'Google sign in with 401 unauthenticated gives helpful contextual message',
    () async {
      final store = MemorySessionStore();
      final gateway = _Gateway(
        credential(),
        loginError: const ApiFailure(ApiFailureKind.unauthenticated),
      );
      final identity = _Identity();
      final controller = SessionController(
        store: store,
        gateway: gateway,
        identityClient: identity,
      );
      await controller.restore();

      expect(await controller.signInWithGoogle(), isFalse);
      expect(
        controller.errorMessage,
        'Verifikasi akun Google gagal. Pastikan akun terdaftar dan periksa koneksi ke server.',
      );
      expect(controller.status, SessionStatus.signedOut);
      expect(store.credential, isNull);
      controller.dispose();
    },
  );

  test('restore clears session on 401 unauthenticated response', () async {
    final store = MemorySessionStore(credential());
    final gateway = _Gateway(
      credential(),
      currentError: const ApiFailure(ApiFailureKind.unauthenticated),
    );
    final identity = _Identity();
    final controller = SessionController(
      store: store,
      gateway: gateway,
      identityClient: identity,
    );
    await controller.restore();

    expect(controller.status, SessionStatus.signedOut);
    expect(store.credential, isNull);
    controller.dispose();
  });

  test(
    'refreshApproval signs out cleanly when session is unauthenticated',
    () async {
      final store = MemorySessionStore(credential());
      final gateway = _Gateway(credential());
      final identity = _Identity();
      final controller = SessionController(
        store: store,
        gateway: gateway,
        identityClient: identity,
      );
      await controller.restore();
      expect(controller.status, SessionStatus.signedIn);

      gateway.currentError = const ApiFailure(ApiFailureKind.unauthenticated);
      await controller.refreshApproval();

      expect(controller.status, SessionStatus.signedOut);
      expect(store.credential, isNull);
      expect(
        controller.errorMessage,
        'Sesi telah kedaluwarsa atau dicabut. Silakan masuk kembali.',
      );
      controller.dispose();
    },
  );

  test('API Google exchange is unauthenticated and decodes approval', () async {
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
            'expires_at': '2030-09-06T16:00:00Z',
            'user': approvedUser.toJson(),
          }),
          200,
        );
      }),
    );

    final result = await client.loginWithGoogle('id-token', 'nonce-value');
    expect(result.accessToken, 'signed-session-token');
    expect(captured.url.path, '/api/v1/auth/google');
    expect(captured.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(captured.body), {
      'id_token': 'id-token',
      'nonce': 'nonce-value',
    });
  });

  testWidgets('login UI only offers Google authentication', (tester) async {
    final controller = SessionController(
      store: MemorySessionStore(),
      gateway: _Gateway(credential()),
      identityClient: _Identity(),
    );
    await controller.restore();
    await tester.pumpWidget(
      MaterialApp(home: LoginView(controller: controller)),
    );

    expect(find.text('Masuk ke PesenHub'), findsOneWidget);
    expect(find.text('Lanjutkan dengan Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('pending account sees locked approval experience', (
    tester,
  ) async {
    const pending = AuthUser(
      id: 'user-2',
      email: 'pe***@example.test',
      displayName: 'Pending Owner',
      role: 'OWNER',
      status: ApprovalStatus.pending,
    );
    final controller = SessionController(
      store: MemorySessionStore(credential(user: pending)),
      gateway: _Gateway(credential(user: pending), current: pending),
      identityClient: _Identity(),
    );
    await controller.restore();
    await tester.pumpWidget(
      MaterialApp(home: ApprovalLockedView(controller: controller)),
    );

    expect(find.text('Menunggu persetujuan Superadmin'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.text('Cek status lagi'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
    controller.dispose();
  });

  test('Superadmin account never unlocks the Owner mobile runtime', () async {
    const superadmin = AuthUser(
      id: 'admin-1',
      email: 'ad***@example.test',
      displayName: 'Superadmin',
      role: 'SUPERADMIN',
      status: ApprovalStatus.approved,
    );
    final controller = SessionController(
      store: MemorySessionStore(credential(user: superadmin)),
      gateway: _Gateway(credential(user: superadmin), current: superadmin),
      identityClient: _Identity(),
    );
    await controller.restore();
    expect(controller.status, SessionStatus.webOnly);
    controller.dispose();
  });
}
