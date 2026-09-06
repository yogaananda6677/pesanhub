import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/remote/api_failure.dart';

class SessionCredential {
  final String accessToken;
  final DateTime expiresAt;

  const SessionCredential({required this.accessToken, required this.expiresAt});

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };

  factory SessionCredential.fromJson(Map<String, dynamic> json) {
    final token = json['access_token'];
    final rawExpiry = json['expires_at'];
    if (token is! String || token.isEmpty || rawExpiry is! String) {
      throw const FormatException('invalid session');
    }
    return SessionCredential(
      accessToken: token,
      expiresAt: DateTime.parse(rawExpiry).toUtc(),
    );
  }
}

abstract class SessionStore {
  Future<SessionCredential?> read();
  Future<void> write(SessionCredential credential);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'pesenhub_session_v1';
  final FlutterSecureStorage _storage;

  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<SessionCredential?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('invalid session');
      final credential = SessionCredential.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (credential.isExpired) {
        await clear();
        return null;
      }
      return credential;
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(SessionCredential credential) =>
      _storage.write(key: _key, value: jsonEncode(credential.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemorySessionStore implements SessionStore {
  SessionCredential? credential;
  MemorySessionStore([this.credential]);

  @override
  Future<SessionCredential?> read() async => credential;
  @override
  Future<void> write(SessionCredential value) async => credential = value;
  @override
  Future<void> clear() async => credential = null;
}

abstract class AuthGateway {
  Future<SessionCredential> login(String username, String password);
}

enum SessionStatus { restoring, signedOut, signingIn, signedIn }

class SessionController extends ChangeNotifier {
  final SessionStore store;
  final AuthGateway gateway;
  SessionStatus status = SessionStatus.restoring;
  SessionCredential? _credential;
  Timer? _expiryTimer;
  String? errorMessage;

  SessionController({required this.store, required this.gateway});

  Future<void> restore() async {
    try {
      _credential = await store.read();
    } catch (_) {
      _credential = null;
      try {
        await store.clear();
      } catch (_) {}
    }
    status = _credential == null
        ? SessionStatus.signedOut
        : SessionStatus.signedIn;
    _scheduleExpiry();
    notifyListeners();
  }

  Future<String?> accessToken() async {
    final credential = _credential ?? await store.read();
    if (credential == null || credential.isExpired) {
      await signOut();
      return null;
    }
    _credential = credential;
    return credential.accessToken;
  }

  Future<bool> signIn(String username, String password) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();
    try {
      final credential = await gateway.login(username.trim(), password);
      if (credential.isExpired) throw const FormatException('expired session');
      await store.write(credential);
      _credential = credential;
      status = SessionStatus.signedIn;
      _scheduleExpiry();
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      errorMessage = failure.kind == ApiFailureKind.unauthenticated
          ? 'Username atau kata sandi salah.'
          : failure.presentationMessage;
    } catch (_) {
      errorMessage = 'Login belum berhasil. Periksa koneksi lalu coba lagi.';
    }
    status = SessionStatus.signedOut;
    notifyListeners();
    return false;
  }

  Future<void> signOut() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _credential = null;
    try {
      await store.clear();
    } finally {
      if (status != SessionStatus.signedOut) {
        status = SessionStatus.signedOut;
        notifyListeners();
      }
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final credential = _credential;
    if (credential == null) return;
    final delay = credential.expiresAt.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      unawaited(signOut());
      return;
    }
    _expiryTimer = Timer(delay, () => unawaited(signOut()));
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
