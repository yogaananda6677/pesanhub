class ApiConfig {
  static const _environmentBaseUrl = String.fromEnvironment(
    'PESENHUB_API_BASE_URL',
  );
  final Uri baseUri;
  final Duration requestTimeout;

  ApiConfig({
    required Uri baseUri,
    this.requestTimeout = const Duration(seconds: 10),
  }) : baseUri = _normalize(baseUri) {
    if (requestTimeout <= Duration.zero) {
      throw const FormatException('request timeout must be positive');
    }
    final localHost = {
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
    }.contains(this.baseUri.host);
    if (this.baseUri.scheme != 'https' && !localHost) {
      throw const FormatException('API base URL must use HTTPS');
    }
  }

  static ApiConfig? fromEnvironment() {
    if (_environmentBaseUrl.isEmpty) return null;
    return ApiConfig(baseUri: Uri.parse(_environmentBaseUrl));
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
