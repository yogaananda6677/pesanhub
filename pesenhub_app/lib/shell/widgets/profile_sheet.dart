import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class ProfileSheet extends StatelessWidget {
  final String? displayName;
  final String? email;
  final String? role;
  final String? branchName;
  final String? branchAddress;
  final Future<void> Function()? onSignOut;

  const ProfileSheet({
    super.key,
    this.displayName,
    this.email,
    this.role,
    this.branchName,
    this.branchAddress,
    this.onSignOut,
  });

  static Future<void> show(
    BuildContext context, {
    String? displayName,
    String? email,
    String? role,
    String? branchName,
    String? branchAddress,
    Future<void> Function()? onSignOut,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProfileSheet(
        displayName: displayName,
        email: email,
        role: role,
        branchName: branchName,
        branchAddress: branchAddress,
        onSignOut: onSignOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : 'Yoga Ananda';
    final initial = effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'Y';
    final effectiveRole = role?.trim().isNotEmpty == true
        ? role!.trim().toUpperCase()
        : 'SUPERADMIN / KASIR';
    final effectiveEmail = email?.trim().isNotEmpty == true
        ? email!.trim()
        : 'admin@jenggirat.com';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Header Card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF0DCD3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                effectiveName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF2B1B16),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                effectiveEmail,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8C7E77),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  effectiveRole,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Detail Gerai & Outlet
                  const Text(
                    'Informasi Gerai Operasional',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2B1B16),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          icon: Icons.storefront_rounded,
                          title: 'Nama Gerai',
                          value: 'Martabak & Terang Bulan Jenggirat',
                        ),
                        const Divider(height: 18, color: Color(0xFFEEEEEE)),
                        _buildInfoRow(
                          icon: Icons.location_on_outlined,
                          title: 'Cabang & Alamat',
                          value: branchAddress != null && branchAddress!.isNotEmpty
                              ? '${branchName ?? "Cabang"} — $branchAddress'
                              : (branchName ?? 'Semua Cabang'),
                        ),
                        const Divider(height: 18, color: Color(0xFFEEEEEE)),
                        _buildInfoRow(
                          icon: Icons.access_time_rounded,
                          title: 'Jam Buka Gerai',
                          value: '16:00 – 24:00 WIB',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Action Buttons
                  if (onSignOut != null) ...[
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _confirmSignOut(context);
                      },
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text('Keluar Akun'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC62828),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF8C7E77)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8C7E77),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2B1B16),
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi Keluar Akun'),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari sesi kasir PesenHub POS?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onSignOut?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}
