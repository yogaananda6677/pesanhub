class ApiConfig {
  static const _environmentBaseUrl = String.fromEnvironment(
    'PESENHUB_API_BASE_URL',
  );
  static const _environmentGoogleServerClientId = String.fromEnvironment(
    'PESENHUB_GOOGLE_SERVER_CLIENT_ID',
  );
  final Uri baseUri;
  final Duration requestTimeout;
  final String googleServerClientId;

  ApiConfig({
    required Uri baseUri,
    this.requestTimeout = const Duration(seconds: 10),
    this.googleServerClientId = '',
  }) : baseUri = _normalize(baseUri) {
    if (requestTimeout <= Duration.zero) {
      throw const FormatException('request timeout must be positive');
    }
    if (this.baseUri.scheme != 'https' &&
        !_isLocalOrPrivateHost(this.baseUri.host)) {
      throw const FormatException('API base URL must use HTTPS');
    }
  }

  static bool _isLocalOrPrivateHost(String host) {
    if (host == 'localhost') return true;
    final ipv4Parts = host.split('.');
    if (ipv4Parts.length == 4) {
      final octets = ipv4Parts.map(int.tryParse).toList();
      if (!octets.contains(null)) {
        final a = octets[0]!;
        final b = octets[1]!;
        if (a == 127) return true;
        if (a == 10) return true;
        if (a == 172 && b >= 16 && b <= 31) return true;
        if (a == 192 && b == 168) return true;
      }
    }
    return false;
  }

  static ApiConfig? fromEnvironment() {
    if (_environmentBaseUrl.isEmpty) return null;
    return ApiConfig(
      baseUri: Uri.parse(_environmentBaseUrl),
      googleServerClientId: _environmentGoogleServerClientId,
    );
  }

  Uri resolve(String relativePath) => baseUri.resolve(relativePath);

  Uri websocketUri(String token) {
    final httpUri = resolve('ws/orders');
    return httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {...httpUri.queryParameters, 'token': token},
    );
  }

  static Uri _normalize(Uri value) {
    if (!value.hasScheme || value.host.isEmpty) {
      throw const FormatException('PESENHUB_API_BASE_URL is invalid');
    }
    final path = value.path.endsWith('/') ? value.path : '${value.path}/';
    return value.replace(path: path, query: null, fragment: null);
  }
}
