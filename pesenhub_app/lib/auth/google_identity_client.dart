import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

abstract class GoogleIdentityClient {
  Future<String> authenticate(String nonce);
  Future<void> signOut();
}

class PlatformGoogleIdentityClient implements GoogleIdentityClient {
  final String serverClientId;
  final GoogleSignIn _googleSignIn;
  bool _initialized = false;

  PlatformGoogleIdentityClient({
    required this.serverClientId,
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  @override
  Future<String> authenticate(String nonce) async {
    if (serverClientId.trim().isEmpty) {
      throw const FormatException('Google OAuth belum dikonfigurasi.');
    }
    if (!_initialized) {
      if (kIsWeb) {
        await _googleSignIn.initialize(clientId: serverClientId, nonce: nonce);
      } else {
        await _googleSignIn.initialize(
          serverClientId: serverClientId,
          nonce: nonce,
        );
      }
      _initialized = true;
    }
    if (!_googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError(
        kIsWeb
            ? 'Login Google interaktif belum didukung langsung pada browser. Silakan masuk menggunakan Username & Password kasir/admin di atas.'
            : 'Google Sign-In interaktif tidak tersedia pada perangkat ini.',
      );
    }
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const FormatException('Google tidak mengembalikan identity token.');
    }
    return idToken;
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}
