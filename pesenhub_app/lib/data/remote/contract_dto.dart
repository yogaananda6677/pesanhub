class PaymentDto {
  static const validMethods = {'CASH', 'MIDTRANS_QRIS'};
  static const validStatuses = {
    'UNPAID',
    'PENDING_PAYMENT',
    'PAID',
    'FAILED',
    'EXPIRED',
    'REFUNDED',
  };

  final String id;
  final String orderId;
  final String method;
  final String status;
  final int amount;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PaymentDto({
    required this.id,
    required this.orderId,
    required this.method,
    required this.status,
    required this.amount,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentDto.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final orderId = _requiredString(json, 'order_id');
    final method = _requiredString(json, 'method');
    final status = _requiredString(json, 'status');
    final amount = json['amount'];
    final version = json['version'];
    final createdAt = DateTime.tryParse(_requiredString(json, 'created_at'));
    final updatedAt = DateTime.tryParse(_requiredString(json, 'updated_at'));
    if (!validMethods.contains(method) ||
        !validStatuses.contains(status) ||
        amount is! int ||
        amount < 1 ||
        version is! int ||
        version < 1 ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('invalid payment contract');
    }
    return PaymentDto(
      id: id,
      orderId: orderId,
      method: method,
      status: status,
      amount: amount,
      version: version,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }
}

class PageMetaDto {
  final int size;
  final String? nextCursor;

  const PageMetaDto({required this.size, this.nextCursor});

  factory PageMetaDto.fromJson(Map<String, dynamic> json) {
    final size = json['size'];
    final nextCursor = json['next_cursor'];
    if (size is! int ||
        size < 1 ||
        size > 100 ||
        (nextCursor != null && nextCursor is! String)) {
      throw const FormatException('invalid pagination contract');
    }
    return PageMetaDto(size: size, nextCursor: nextCursor as String?);
  }
}

class ErrorEnvelopeDto {
  final String code;
  final String message;
  final String requestId;
  final List<ErrorDetailDto> details;

  const ErrorEnvelopeDto({
    required this.code,
    required this.message,
    required this.requestId,
    required this.details,
  });

  factory ErrorEnvelopeDto.fromJson(Map<String, dynamic> json) {
    final rawError = json['error'];
    if (rawError is! Map) {
      throw const FormatException('missing error envelope');
    }
    final error = Map<String, dynamic>.from(rawError);
    final code = _requiredString(error, 'code');
    final message = _requiredString(error, 'message');
    final requestId = _requiredString(error, 'request_id');
    if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(code)) {
      throw const FormatException('invalid error code');
    }
    final rawDetails = error['details'];
    if (rawDetails != null && rawDetails is! List) {
      throw const FormatException('invalid error details');
    }
    final details = (rawDetails as List? ?? const [])
        .map((value) {
          if (value is! Map) {
            throw const FormatException('invalid error detail');
          }
          final detail = Map<String, dynamic>.from(value);
          return ErrorDetailDto(
            field: _requiredString(detail, 'field'),
            reason: _requiredString(detail, 'reason'),
          );
        })
        .toList(growable: false);
    return ErrorEnvelopeDto(
      code: code,
      message: message,
      requestId: requestId,
      details: details,
    );
  }
}

class ErrorDetailDto {
  final String field;
  final String reason;

  const ErrorDetailDto({required this.field, required this.reason});
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('missing $key');
  }
  return value;
}
