import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/settings/controllers/whatsapp_settings_controller.dart';
import 'package:pesenhub_app/settings/models/employee.dart';
import 'package:pesenhub_app/settings/models/whatsapp_settings_data.dart';
import 'package:pesenhub_app/settings/views/app_policy_view.dart';
import 'package:pesenhub_app/settings/views/device_printer_view.dart';
import 'package:pesenhub_app/settings/views/employee_management_view.dart';
import 'package:pesenhub_app/settings/views/integration_services_view.dart';
import 'package:pesenhub_app/settings/views/outlet_operational_view.dart';
import 'package:pesenhub_app/settings/widgets/whatsapp_qr_dialog.dart';
import 'package:pesenhub_app/shell/destination_views.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  group('Employee Model Tests', () {
    test('parses Employee json properly', () {
      final json = {
        'id': 'emp-001',
        'email': 'kasir@jenggirat.com',
        'display_name': 'Ahmad Fauzi',
        'role': 'CASHIER',
        'status': 'APPROVED',
        'branch_id': 'b-01',
        'branch_name': 'Cabang Utama Banyuwangi',
      };

      final emp = Employee.fromJson(json);
      expect(emp.id, 'emp-001');
      expect(emp.email, 'kasir@jenggirat.com');
      expect(emp.displayName, 'Ahmad Fauzi');
      expect(emp.role, 'CASHIER');
      expect(emp.roleDisplay, 'Kasir');
      expect(emp.status, 'APPROVED');
      expect(emp.statusDisplay, 'Aktif');
      expect(emp.isActive, isTrue);
      expect(emp.branchName, 'Cabang Utama Banyuwangi');

      final copied = emp.copyWith(displayName: 'Ahmad F.', status: 'SUSPENDED');
      expect(copied.displayName, 'Ahmad F.');
      expect(copied.status, 'SUSPENDED');
      expect(copied.isActive, isFalse);
      expect(copied.statusDisplay, 'Nonaktif');
    });

    test('serializes Employee to json correctly', () {
      const emp = Employee(
        id: 'emp-002',
        email: 'manager@jenggirat.com',
        displayName: 'Siti Nurhaliza',
        role: 'MANAGER',
        status: 'APPROVED',
      );

      final map = emp.toJson();
      expect(map['id'], 'emp-002');
      expect(map['display_name'], 'Siti Nurhaliza');
      expect(map['role'], 'MANAGER');
      expect(emp.roleDisplay, 'Manajer Outlet');
    });
  });

  group('SettingsDestinationView (Screen 1) Tests', () {
    testWidgets(
      'renders terracotta profile card, quick stats, and 5 main menu items',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: SettingsDestinationView(
                userName: 'Yoga Ananda',
                userEmail: 'yogaanandaxx1212@gmail.com',
                userRole: 'Superadmin',
                isAdmin: true,
                branchName: 'Semua Cabang',
              ),
            ),
          ),
        );

        // Verify Header
        expect(find.text('Akun'), findsOneWidget);
        expect(
          find.text('Kelola profil dan konfigurasi aplikasi'),
          findsOneWidget,
        );

        // Verify Profile Info
        expect(find.text('Yoga Ananda'), findsOneWidget);
        expect(find.text('yogaanandaxx1212@gmail.com'), findsOneWidget);
        expect(find.text('ADMIN'), findsOneWidget);
        expect(find.text('SUPERADMIN'), findsNothing);
        expect(find.text('Martabak & Terang Bulan Jenggirat'), findsOneWidget);

        // Verify 3 Quick Stat Cards
        expect(find.text('CABANG'), findsOneWidget);
        expect(find.text('JAM KERJA'), findsOneWidget);
        expect(find.text('ROLE'), findsOneWidget);

        // Verify 5 Main Menu Tiles
        expect(find.text('Manajemen Karyawan'), findsOneWidget);
        expect(find.text('Outlet & Operasional'), findsOneWidget);
        expect(find.text('Perangkat & Printer'), findsOneWidget);
        expect(find.text('Integrasi & Layanan'), findsOneWidget);
        expect(find.text('Informasi & Kebijakan'), findsOneWidget);

        // Compatibility badges for existing test assertions
        expect(find.text('Informasi Outlet'), findsOneWidget);
        expect(find.text('Integrasi WhatsApp (GOWA)'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping profile card opens Edit Name Dialog and updates local name',
      (tester) async {
        String? savedName;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SettingsDestinationView(
                userName: 'Yoga Ananda',
                userEmail: 'yoga@gmail.com',
                isAdmin: true,
                onUpdateDisplayName: (newName) async {
                  savedName = newName;
                },
              ),
            ),
          ),
        );

        // Tap profile card to trigger dialog
        await tester.tap(find.text('Yoga Ananda'));
        await tester.pumpAndSettle();

        // Dialog opens
        expect(find.text('Ubah Nama Profil'), findsOneWidget);
        expect(find.text('Simpan'), findsOneWidget);

        // Enter new name
        await tester.enterText(find.byType(TextField), 'Yoga Ananda Sabila');
        await tester.tap(find.text('Simpan'));
        await tester.pumpAndSettle();

        // Verify callback was called and dialog closed
        expect(savedName, 'Yoga Ananda Sabila');
        expect(find.text('Ubah Nama Profil'), findsNothing);
        expect(find.text('Yoga Ananda Sabila'), findsOneWidget);
      },
    );
  });

  group('Sub-Screens Navigation & Rendering Tests', () {
    testWidgets(
      'EmployeeManagementView (Screen 3) renders and filters employees',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const EmployeeManagementView(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Manajemen Karyawan'), findsOneWidget);
        expect(find.text('Undang Kasir'), findsOneWidget);
        expect(find.text('SUPERADMIN'), findsNothing);

        // Check fallback employee list
        expect(find.text('Yoga Ananda Sabila Rizqi'), findsOneWidget);
        expect(find.text('Siti Nurhaliza'), findsOneWidget);

        // Test Search Filter
        await tester.enterText(find.byType(TextField), 'Dewi');
        await tester.pumpAndSettle();

        expect(find.text('Dewi Lestari'), findsOneWidget);
        expect(find.text('Siti Nurhaliza'), findsNothing);
      },
    );

    testWidgets(
      'EmployeeManagementView displays lock notice and hides action menu when isAdmin is false',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const EmployeeManagementView(isAdmin: false),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Undang Kasir'), findsNothing);
        expect(
          find.text(
            'Fitur undang kasir hanya dapat diakses oleh Admin Outlet.',
          ),
          findsOneWidget,
        );
        expect(find.byType(PopupMenuButton<String>), findsNothing);
      },
    );

    testWidgets(
      'EmployeeManagementView: admin cannot manage fellow admin, but can manage cashier',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const EmployeeManagementView(isAdmin: true),
          ),
        );
        await tester.pumpAndSettle();

        // There should be a "Terkunci" indicator for fellow Admin
        expect(find.text('Terkunci'), findsAtLeastNWidgets(1));

        // Cashiers should have action menus (PopupMenuButton), but not fellow Admins
        // In fallback list: 3 cashiers (Siti, Ahmad, Rizky) have menus; Admin (Yoga) and Manager (Dewi) are locked
        expect(find.byType(PopupMenuButton<String>), findsNWidgets(3));
      },
    );

    testWidgets(
      'EmployeeManagementView dialog supports 2 onboarding methods (Google Invite & Create Account)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const EmployeeManagementView(isAdmin: true),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Undang Kasir
        await tester.tap(find.text('Undang Kasir'));
        await tester.pumpAndSettle();

        // Dialog should be open with 2 methods
        expect(find.text('Undang / Tambah Kasir'), findsOneWidget);
        expect(find.text('Undang via Google'), findsOneWidget);
        expect(find.text('Buatkan Akun'), findsOneWidget);

        // Default tab is 0 (Google)
        expect(find.text('Kirim Undangan Google'), findsOneWidget);
        expect(find.text('Email Akun Google'), findsOneWidget);

        // Switch to tab 1 (Buatkan Akun)
        await tester.tap(find.text('Buatkan Akun'));
        await tester.pumpAndSettle();

        // Verify Role is locked to Cashier only (no role dropdown)
        expect(find.text('Peran: Kasir Outlet'), findsOneWidget);
        expect(find.text('CASHIER'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      },
    );

    testWidgets(
      'WhatsAppQrDialog supports both QR scan and Pairing Code methods',
      (tester) async {
        final mockController = WhatsAppSettingsController(
          customPair: ({deviceId, method, phone}) async {
            if (method == 'code') {
              return const WhatsAppPairResult(
                isAlreadyLoggedIn: false,
                status: 'WAITING_PAIR_CODE',
                deviceId: 'pesenhub-dev',
                method: 'code',
                pairCode: 'EK1N-D4A9',
                phone: '+628123456789',
                qrDuration: 0,
                qrLink: '',
                qrProxyUrl: '',
              );
            }
            return const WhatsAppPairResult(
              isAlreadyLoggedIn: false,
              status: 'WAITING_QR_SCAN',
              deviceId: 'pesenhub-dev',
              method: 'qr',
              qrDuration: 30,
              qrLink: 'http://test.com/qr.png',
              qrProxyUrl: '/api/v1/settings/whatsapp/qr-image?url=test',
            );
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () =>
                      WhatsAppQrDialog.show(ctx, controller: mockController),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Check dialog title and tabs
        expect(find.text('Hubungkan WhatsApp (GOWA)'), findsOneWidget);
        expect(find.text('Pindai QR'), findsOneWidget);
        expect(find.text('Kode Tautan'), findsOneWidget);
        expect(find.text('Cara Pindai QR:'), findsOneWidget);

        // Switch to Tab 1 (Kode Tautan)
        await tester.tap(find.text('Kode Tautan'));
        await tester.pumpAndSettle();

        expect(find.text('Nomor WhatsApp Outlet'), findsOneWidget);
        expect(find.text('Dapatkan Kode Tautan'), findsOneWidget);
        expect(find.text('Cara Menautkan dengan Kode:'), findsOneWidget);

        // Enter phone number and request code
        await tester.enterText(find.byType(TextField), '08123456789');
        await tester.tap(find.text('Dapatkan Kode Tautan'));
        await tester.pumpAndSettle();

        expect(find.text('EK1N-D4A9'), findsOneWidget);
        expect(find.text('Salin Kode'), findsOneWidget);
      },
    );

    testWidgets(
      'OutletOperationalView (Screen 4) renders operational hours and branches',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const OutletOperationalView(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Outlet & Operasional'), findsOneWidget);
        expect(find.text('Martabak & Terang Bulan Jenggirat'), findsOneWidget);
        expect(find.text('Status Layanan Kasir'), findsOneWidget);
        expect(find.text('Cabang Utama Banyuwangi'), findsOneWidget);
      },
    );

    testWidgets(
      'DevicePrinterView (Screen 5) renders printer details and test print button',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const DevicePrinterView(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Perangkat & Printer'), findsOneWidget);
        expect(find.text('PRINTER STRUK UTAMA'), findsOneWidget);
        expect(find.text('Xprinter XP-58II'), findsAtLeast(1));
        expect(find.text('Uji Cetak Struk (Test Print)'), findsOneWidget);
      },
    );

    testWidgets(
      'IntegrationServicesView (Screen 6) renders WhatsApp integration and cloud services',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const IntegrationServicesView(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Integrasi & Layanan'), findsOneWidget);
        expect(find.text('Backup Google Drive Harian'), findsOneWidget);
        expect(find.text('Webhook Transaksi Masuk'), findsOneWidget);
      },
    );

    testWidgets(
      'AppPolicyView (Screen 2) renders legal policy links and app info',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const AppPolicyView()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Informasi & Kebijakan'), findsOneWidget);
        expect(find.text('Kebijakan Privasi'), findsOneWidget);
        expect(find.text('Syarat & Ketentuan Layanan'), findsOneWidget);
        expect(find.text('Catatan Rilis & Pembaruan'), findsOneWidget);
      },
    );
  });
}
