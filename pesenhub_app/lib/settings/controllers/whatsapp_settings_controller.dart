import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/remote/api_config.dart';
import '../models/whatsapp_settings_data.dart';

class WhatsAppSettingsController extends ChangeNotifier {
  final http.Client _client;
  final String baseUrl;
  final Future<String?> Function()? getAuthToken;

  final Future<WhatsAppSettingsData> Function()? customFetchSettings;
  final Future<WhatsAppPairResult> Function({String? deviceId})? customPair;
  final Future<void> Function({String? deviceId})? customDisconnect;

  WhatsAppSettingsData _data = WhatsAppSettingsData.initial;
  bool _isLoading = false;
  String? _errorMessage;

  WhatsAppPairResult? _currentPairResult;
  bool _isPairing = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  WhatsAppSettingsController({
    String? baseUrl,
    this.getAuthToken,
    this.customFetchSettings,
    this.customPair,
    this.customDisconnect,
    http.Client? client,
    WhatsAppSettingsData? initialData,
  }) : baseUrl = _resolveBaseUrl(baseUrl),
       _client = client ?? http.Client(),
       _data = initialData ?? WhatsAppSettingsData.initial;

  static String _resolveBaseUrl(String? provided) {
    if (provided != null && provided.isNotEmpty) {
      return _trimApiV1(provided);
    }
    final env = ApiConfig.fromEnvironment();
    if (env != null) {
      return _trimApiV1(env.baseUri.origin);
    }
    return 'http://localhost:8080';
  }

  static String _trimApiV1(String url) {
    var trimmed = url.trimRight();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.endsWith('/api/v1')) {
      trimmed = trimmed.substring(0, trimmed.length - '/api/v1'.length);
    }
    return trimmed;
  }

  WhatsAppSettingsData get data => _data;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  WhatsAppPairResult? get currentPairResult => _currentPairResult;
  bool get isPairing => _isPairing;
  int get remainingSeconds => _remainingSeconds;

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (getAuthToken != null) {
      final token = await getAuthToken!();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<void> loadSettings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (customFetchSettings != null) {
        _data = await customFetchSettings!();
      } else {
        final uri = Uri.parse('$baseUrl/api/v1/settings/whatsapp');
        final headers = await _headers();
        final response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final payload = (body['data'] is Map<String, dynamic>)
              ? body['data'] as Map<String, dynamic>
              : body;
          _data = WhatsAppSettingsData.fromJson(payload);
        } else {
          _data = const WhatsAppSettingsData(
            isConnected: false,
            status: 'DISCONNECTED',
            gatewayState: 'DOWN',
            deviceId: '',
            phoneMasked: '-',
            privacyNotice:
                'Nomor telepon dan pesan pelanggan disanitasi otomatis sebelum disimpan.',
          );
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
      _data = const WhatsAppSettingsData(
        isConnected: false,
        status: 'DISCONNECTED',
        gatewayState: 'DOWN',
        deviceId: '',
        phoneMasked: '-',
        privacyNotice:
            'Nomor telepon dan pesan pelanggan disanitasi otomatis sebelum disimpan.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<WhatsAppPairResult?> requestPairing({String? deviceId}) async {
    _isPairing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      WhatsAppPairResult result;
      if (customPair != null) {
        result = await customPair!(deviceId: deviceId);
      } else {
        final uri = Uri.parse('$baseUrl/api/v1/settings/whatsapp/pair');
        final headers = await _headers();
        final payload = jsonEncode({'device_id': deviceId ?? _data.deviceId});
        final response = await _client
            .post(uri, headers: headers, body: payload)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final data = (body['data'] is Map<String, dynamic>)
              ? body['data'] as Map<String, dynamic>
              : body;
          result = WhatsAppPairResult.fromJson(data);
        } else {
          throw Exception(
            'Gagal meminta kode QR (status ${response.statusCode})',
          );
        }
      }

      _currentPairResult = result;
      _startCountdown(result.qrDuration);

      if (result.isAlreadyLoggedIn) {
        await loadSettings();
      }

      return result;
    } catch (e) {
      _errorMessage = e.toString();
      _isPairing = false;
      return null;
    } finally {
      notifyListeners();
    }
  }

  void stopPairing() {
    _countdownTimer?.cancel();
    _currentPairResult = null;
    _remainingSeconds = 0;
    _isPairing = false;
    notifyListeners();
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _isPairing = true;
    _remainingSeconds = seconds > 0 ? seconds : 30;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        _isPairing = false;
        timer.cancel();
        notifyListeners();
      }
    });
  }

  Future<bool> checkConnectionStatus() async {
    try {
      await loadSettings();
      return _data.isConnected;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect({String? deviceId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (customDisconnect != null) {
        await customDisconnect!(deviceId: deviceId);
      } else {
        final uri = Uri.parse('$baseUrl/api/v1/settings/whatsapp/disconnect');
        final headers = await _headers();
        final payload = jsonEncode({'device_id': deviceId ?? _data.deviceId});
        await _client
            .post(uri, headers: headers, body: payload)
            .timeout(const Duration(seconds: 5));
      }
      await loadSettings();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
