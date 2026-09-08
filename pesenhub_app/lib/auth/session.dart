import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/remote/api_failure.dart';
import 'google_identity_client.dart';

enum ApprovalStatus { pending, approved, rejected, suspended }

class AuthUser {
  final String id;
  final String email;
  final String displayName;
  final String role;
  final ApprovalStatus status;

  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final email = json['email'];
    final displayName = json['display_name'];
    final role = json['role'];
    final rawStatus = json['status'];
    if (id is! String ||
        id.isEmpty ||
        email is! String ||
        displayName is! String ||
        role is! String ||
        rawStatus is! String) {
      throw const FormatException('invalid authenticated user');
    }
    final status = switch (rawStatus) {
      'PENDING_APPROVAL' => ApprovalStatus.pending,
      'APPROVED' => ApprovalStatus.approved,
      'REJECTED' => ApprovalStatus.rejected,
      'SUSPENDED' => ApprovalStatus.suspended,
      _ => throw const FormatException('invalid approval status'),
    };
    return AuthUser(
      id: id,
      email: email,
      displayName: displayName,
      role: role,
      status: status,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'role': role,
    'status': switch (status) {
      ApprovalStatus.pending => 'PENDING_APPROVAL',
      ApprovalStatus.approved => 'APPROVED',
      ApprovalStatus.rejected => 'REJECTED',
      ApprovalStatus.suspended => 'SUSPENDED',
    },
  };
}

class SessionCredential {
  final String accessToken;
  final DateTime expiresAt;
  final AuthUser user;
  final DateTime approvalCheckedAt;

  SessionCredential({
    required this.accessToken,
    required this.expiresAt,
    required this.user,
    DateTime? approvalCheckedAt,
  }) : approvalCheckedAt = (approvalCheckedAt ?? DateTime.now()).toUtc();

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
  bool get hasFreshApproval =>
      user.status == ApprovalStatus.approved &&
      DateTime.now().toUtc().difference(approvalCheckedAt) <
          const Duration(minutes: 2);

  SessionCredential withUser(AuthUser value) => SessionCredential(
    accessToken: accessToken,
    expiresAt: expiresAt,
    user: value,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'approval_checked_at': approvalCheckedAt.toIso8601String(),
    'user': user.toJson(),
  };

  factory SessionCredential.fromJson(Map<String, dynamic> json) {
    final token = json['access_token'];
    final rawExpiry = json['expires_at'];
    final rawCheckedAt = json['approval_checked_at'];
    final rawUser = json['user'];
    if (token is! String ||
        token.isEmpty ||
        rawExpiry is! String ||
        rawUser is! Map) {
      throw const FormatException('invalid session');
    }
    return SessionCredential(
      accessToken: token,
      expiresAt: DateTime.parse(rawExpiry).toUtc(),
      approvalCheckedAt: rawCheckedAt is String
          ? DateTime.parse(rawCheckedAt).toUtc()
          : DateTime.now().toUtc(),
      user: AuthUser.fromJson(Map<String, dynamic>.from(rawUser)),
    );
  }
}

abstract class SessionStore {
  Future<SessionCredential?> read();
  Future<void> write(SessionCredential credential);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'pesenhub_google_session_v2';
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
  Future<String> createGoogleChallenge();
  Future<SessionCredential> loginWithGoogle(String idToken, String nonce);
  Future<AuthUser> currentUser();
  Future<void> logout();
}

enum SessionStatus {
  restoring,
  signedOut,
  signingIn,
  pendingApproval,
  rejected,
  suspended,
  webOnly,
  offlineLocked,
  signedIn,
}

class SessionController extends ChangeNotifier {
  final SessionStore store;
  final AuthGateway gateway;
  final GoogleIdentityClient identityClient;
  SessionStatus status = SessionStatus.restoring;
  SessionCredential? _credential;
  Timer? _expiryTimer;
  String? errorMessage;

  SessionController({
    required this.store,
    required this.gateway,
    required this.identityClient,
  });

  AuthUser? get user => _credential?.user;

  Future<void> restore() async {
    try {
      _credential = await store.read();
      if (_credential?.isExpired ?? false) {
        _credential = null;
        await store.clear();
      }
      if (_credential == null) {
        status = SessionStatus.signedOut;
      } else {
        try {
          await _refreshUser();
        } on ApiFailure catch (failure) {
          if (failure.kind == ApiFailureKind.unauthenticated) {
            _credential = null;
            await store.clear();
            status = SessionStatus.signedOut;
          } else {
            status = _credential!.hasFreshApproval
                ? SessionStatus.signedIn
                : SessionStatus.offlineLocked;
          }
        } catch (_) {
          status = _credential!.hasFreshApproval
              ? SessionStatus.signedIn
              : SessionStatus.offlineLocked;
        }
      }
    } catch (_) {
      _credential = null;
      status = SessionStatus.signedOut;
      try {
        await store.clear();
      } catch (_) {}
    }
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

  Future<bool> signInWithGoogle() async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();
    try {
      final nonce = await gateway.createGoogleChallenge();
      final idToken = await identityClient.authenticate(nonce);
      final credential = await gateway.loginWithGoogle(idToken, nonce);
      if (credential.isExpired) throw const FormatException('expired session');
      await store.write(credential);
      _credential = credential;
      _applyUserStatus(credential.user);
      _scheduleExpiry();
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      if (failure.kind == ApiFailureKind.unauthenticated) {
        errorMessage =
            'Verifikasi akun Google gagal. Pastikan akun terdaftar dan periksa koneksi ke server.';
      } else if (failure.kind == ApiFailureKind.conflict) {
        errorMessage =
            'Akun Google ini sudah terhubung dengan peran lain.';
      } else if (failure.kind == ApiFailureKind.network) {
        errorMessage =
            'Koneksi ke server backend gagal. Pastikan perangkat terhubung ke server.';
      } else {
        errorMessage = failure.presentationMessage;
      }
    } on FormatException catch (e) {
      errorMessage = e.message;
    } on UnsupportedError catch (e) {
      errorMessage =
          e.message ?? 'Google Sign-In tidak didukung pada perangkat ini.';
    } catch (_) {
      errorMessage =
          'Login Google belum berhasil. Periksa koneksi lalu coba lagi.';
    }
    status = SessionStatus.signedOut;
    notifyListeners();
    return false;
  }

  Future<void> refreshApproval() async {
    if (_credential == null) return;
    errorMessage = null;
    try {
      await _refreshUser();
    } on ApiFailure catch (failure) {
      if (failure.kind == ApiFailureKind.unauthenticated) {
        await signOut();
        errorMessage =
            'Sesi telah kedaluwarsa atau dicabut. Silakan masuk kembali.';
        return;
      }
      status = SessionStatus.offlineLocked;
      errorMessage =
          'Status belum dapat diperiksa. Hubungkan ke backend lalu coba lagi.';
    } catch (_) {
      status = SessionStatus.offlineLocked;
      errorMessage =
          'Status belum dapat diperiksa. Hubungkan ke backend lalu coba lagi.';
    }
    notifyListeners();
  }

  Future<void> _refreshUser() async {
    final user = await gateway.currentUser();
    _credential = _credential!.withUser(user);
    await store.write(_credential!);
    _applyUserStatus(user);
  }

  void _applyUserStatus(AuthUser user) {
    if (user.role != 'OWNER') {
      status = SessionStatus.webOnly;
      return;
    }
    status = switch (user.status) {
      ApprovalStatus.approved => SessionStatus.signedIn,
      ApprovalStatus.pending => SessionStatus.pendingApproval,
      ApprovalStatus.rejected => SessionStatus.rejected,
      ApprovalStatus.suspended => SessionStatus.suspended,
    };
  }

  Future<void> signOut() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_credential != null) {
      try {
        await gateway.logout();
      } catch (_) {}
    }
    try {
      await identityClient.signOut();
    } catch (_) {}
    _credential = null;
    try {
      await store.clear();
    } finally {
      status = SessionStatus.signedOut;
      notifyListeners();
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
