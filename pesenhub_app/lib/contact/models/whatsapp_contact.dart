class WhatsAppContact {
  final String id;
  final String branchId;
  final String phoneE164;
  final String name;
  final String contactType;
  final bool autoReplyEnabled;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WhatsAppContact({
    required this.id,
    required this.branchId,
    required this.phoneE164,
    required this.name,
    this.contactType = 'CUSTOMER',
    this.autoReplyEnabled = true,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCustomer => contactType == 'CUSTOMER';
  bool get isNonCustomer => contactType == 'NON_CUSTOMER';
  bool get isBlacklisted => contactType == 'BLACKLIST';
  bool get isVendor => contactType == 'VENDOR';
  bool get isPersonal => contactType == 'PERSONAL';

  factory WhatsAppContact.fromJson(Map<String, dynamic> json) {
    return WhatsAppContact(
      id: json['id'] as String? ?? '',
      branchId: json['branch_id'] as String? ?? '',
      phoneE164: json['phone_e164'] as String? ?? '',
      name: json['name'] as String? ?? '',
      contactType: json['contact_type'] as String? ?? 'CUSTOMER',
      autoReplyEnabled: json['auto_reply_enabled'] as bool? ?? true,
      notes: json['notes'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'branch_id': branchId,
      'phone_e164': phoneE164,
      'name': name,
      'contact_type': contactType,
      'auto_reply_enabled': autoReplyEnabled,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WhatsAppContact copyWith({
    String? id,
    String? branchId,
    String? phoneE164,
    String? name,
    String? contactType,
    bool? autoReplyEnabled,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WhatsAppContact(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      phoneE164: phoneE164 ?? this.phoneE164,
      name: name ?? this.name,
      contactType: contactType ?? this.contactType,
      autoReplyEnabled: autoReplyEnabled ?? this.autoReplyEnabled,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
