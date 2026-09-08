/// Data model representing the status and properties of WhatsApp GOWA integration.
class WhatsAppSettingsData {
  final bool isConnected;
  final String status; // 'CONNECTED', 'DISCONNECTED', 'GATEWAY_DOWN'
  final String gatewayState;
  final String deviceId;
  final String phoneMasked;
  final String? jid;
  final String privacyNotice;

  const WhatsAppSettingsData({
    required this.isConnected,
    required this.status,
    required this.gatewayState,
    required this.deviceId,
    required this.phoneMasked,
    this.jid,
    required this.privacyNotice,
  });

  factory WhatsAppSettingsData.fromJson(Map<String, dynamic> json) {
    return WhatsAppSettingsData(
      isConnected: json['is_connected'] as bool? ?? false,
      status: json['status'] as String? ?? 'DISCONNECTED',
      gatewayState: json['gateway_state'] as String? ?? 'UNKNOWN',
      deviceId: json['device_id'] as String? ?? '',
      phoneMasked: json['phone_masked'] as String? ?? '-',
      jid: json['jid'] as String?,
      privacyNotice: json['privacy_notice'] as String? ?? '',
    );
  }

  static const initial = WhatsAppSettingsData(
    isConnected: false,
    status: 'DISCONNECTED',
    gatewayState: 'UP',
    deviceId: '',
    phoneMasked: '-',
    privacyNotice:
        'Nomor telepon dan pesan pelanggan disanitasi dengan enkripsi dan PII masking otomatis sebelum disimpan.',
  );
}

/// Data model representing the result of a WhatsApp QR pairing request.
class WhatsAppPairResult {
  final bool isAlreadyLoggedIn;
  final String status;
  final String deviceId;
  final int qrDuration;
  final String qrLink;
  final String qrProxyUrl;

  const WhatsAppPairResult({
    required this.isAlreadyLoggedIn,
    required this.status,
    required this.deviceId,
    required this.qrDuration,
    required this.qrLink,
    required this.qrProxyUrl,
  });

  factory WhatsAppPairResult.fromJson(Map<String, dynamic> json) {
    return WhatsAppPairResult(
      isAlreadyLoggedIn: json['is_already_logged_in'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      qrDuration: (json['qr_duration'] as num?)?.toInt() ?? 30,
      qrLink: json['qr_link'] as String? ?? '',
      qrProxyUrl: json['qr_proxy_url'] as String? ?? '',
    );
  }
}
