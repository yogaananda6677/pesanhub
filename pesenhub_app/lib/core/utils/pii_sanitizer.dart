/// PiiSanitizer enforces Invariant 11 (PII Sanitization).
/// Guarantees that customer sensitive data (phone numbers, credentials)
/// are masked or excluded before saving to local persistent storage.
class PiiSanitizer {
  static final RegExp _sensitiveKeyPattern = RegExp(
    r'(token|secret|password|auth|bearer|credential|key|apikey)',
    caseSensitive: false,
  );

  /// Masks a raw phone number into a sanitized form (e.g. 0812****7890).
  /// If the phone number is already masked, returns as-is.
  /// If null or empty, returns empty string.
  static String maskPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return '';
    }

    final trimmed = phone.trim();

    // Already masked check
    if (trimmed.contains('*')) {
      return trimmed;
    }

    // Special labels like 'Kasir' or non-digits
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return trimmed;
    }
    if (digitsOnly.length < 7) {
      if (trimmed.length <= 4) return trimmed;
      final prefix = trimmed.substring(0, 2);
      final suffix = trimmed.substring(trimmed.length - 2);
      final mask = '*' * (trimmed.length - 4);
      return '$prefix$mask$suffix';
    }

    // Standard phone masking: keep first 4 digits, last 4 digits, replace middle with 4 asterisks
    final prefix = digitsOnly.substring(0, 4);
    final suffix = digitsOnly.substring(digitsOnly.length - 4);
    return '$prefix****$suffix';
  }

  /// Verifies that a key to be saved in metadata or local tables does not contain
  /// authentication tokens or sensitive credentials.
  static bool isSensitiveStorageKey(String key) {
    return _sensitiveKeyPattern.hasMatch(key);
  }

  /// Validates a metadata key before writing to storage.
  /// Throws [ArgumentError] if the key violates security invariants.
  static void validateMetadataKey(String key) {
    if (isSensitiveStorageKey(key)) {
      throw ArgumentError(
        'Keamanan ditolak: Kredensial atau token sensitif ("$key") dilarang disimpan di local database (Invariant 11).',
      );
    }
  }
}
