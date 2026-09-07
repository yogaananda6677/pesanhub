import 'package:google_sign_in/google_sign_in.dart';

abstract class GoogleIdentityClient {
  Future<String> authenticate(String nonce);
  Future<void> signOut();
}

class PlatformGoogleIdentityClient implements GoogleIdentityClient {
  final String serverClientId;
  final GoogleSignIn _googleSignIn;

  PlatformGoogleIdentityClient({required this.serverClientId})
    : _googleSignIn = GoogleSignIn.instance;

  @override
  Future<String> authenticate(String nonce) async {
    if (serverClientId.trim().isEmpty) {
      throw const FormatException('Google OAuth belum dikonfigurasi.');
    }
    await _googleSignIn.initialize(
      serverClientId: serverClientId,
      nonce: nonce,
    );
    if (!_googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError('Google Sign-In interaktif tidak tersedia.');
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
