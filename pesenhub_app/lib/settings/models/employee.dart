/// Employee model representing staff/cashiers in PesenHub.
class Employee {
  final String id;
  final String email;
  final String displayName;
  final String role;
  final String status;
  final String? branchId;
  final String? branchName;
  final DateTime? createdAt;

  const Employee({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    this.branchId,
    this.branchName,
    this.createdAt,
  });

  bool get isActive =>
      status.toUpperCase() == 'APPROVED' ||
      status.toUpperCase() == 'ACTIVE' ||
      status.toUpperCase() == 'AKTIF';

  bool get isCashier => role.toUpperCase() == 'CASHIER';

  bool get isAdmin =>
      role.toUpperCase() == 'ADMIN' ||
      role.toUpperCase() == 'SUPERADMIN' ||
      role.toUpperCase() == 'OWNER';

  String get roleDisplay {
    switch (role.toUpperCase()) {
      case 'SUPERADMIN':
      case 'ADMIN':
      case 'OWNER':
        return 'Admin Outlet';
      case 'MANAGER':
        return 'Manajer Outlet';
      case 'CASHIER':
      default:
        return 'Kasir';
    }
  }

  String get statusDisplay {
    if (status.toUpperCase() == 'INVITED' ||
        status.toUpperCase() == 'PENDING') {
      return 'Menunggu Undangan';
    }
    return isActive ? 'Aktif' : 'Nonaktif';
  }

  Employee copyWith({
    String? id,
    String? email,
    String? displayName,
    String? role,
    String? status,
    String? branchId,
    String? branchName,
    DateTime? createdAt,
  }) {
    return Employee(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      status: status ?? this.status,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: (json['display_name'] as String?)?.trim().isNotEmpty == true
          ? (json['display_name'] as String).trim()
          : (json['email'] as String? ?? 'Karyawan'),
      role: json['role'] as String? ?? 'CASHIER',
      status: json['status'] as String? ?? 'APPROVED',
      branchId: json['branch_id'] as String?,
      branchName: json['branch_name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'role': role,
    'status': status,
    if (branchId != null) 'branch_id': branchId,
    if (branchName != null) 'branch_name': branchName,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}
