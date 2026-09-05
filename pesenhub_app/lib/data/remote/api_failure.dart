enum ApiFailureKind {
  unauthenticated,
  forbidden,
  validation,
  conflict,
  server,
  network,
  invalidResponse,
}

class ApiFailure implements Exception {
  final ApiFailureKind kind;
  final int? statusCode;
  final String? requestId;

  const ApiFailure(this.kind, {this.statusCode, this.requestId});

  bool get isTransient =>
      kind == ApiFailureKind.server || kind == ApiFailureKind.network;

  String get presentationMessage {
    switch (kind) {
      case ApiFailureKind.unauthenticated:
        return 'Sesi tidak valid. Silakan autentikasi ulang.';
      case ApiFailureKind.forbidden:
        return 'Akun ini tidak memiliki akses ke antrean.';
      case ApiFailureKind.validation:
        return 'Data ditolak server. Periksa kembali isian pesanan.';
      case ApiFailureKind.conflict:
        return 'Data berubah di server. Muat ulang sebelum melanjutkan.';
      case ApiFailureKind.server:
        return 'Server sedang bermasalah. Percobaan ulang dijadwalkan.';
      case ApiFailureKind.network:
        return 'Koneksi terputus. Data lokal dan outbox tetap aman.';
      case ApiFailureKind.invalidResponse:
        return 'Respons server tidak sesuai kontrak aplikasi.';
    }
  }

  @override
  String toString() => 'ApiFailure(${kind.name}, requestId: $requestId)';
}
