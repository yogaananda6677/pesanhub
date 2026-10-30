import 'package:flutter/material.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../models/cash_shift.dart';

class CashShiftController extends ChangeNotifier {
  final ShiftRemoteGateway gateway;
  final String? branchId;

  CashShift? _activeShift;
  List<CashShift> _history = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  CashShiftController({required this.gateway, this.branchId});

  CashShift? get activeShift => _activeShift;
  CashShift? get currentShift => _activeShift;
  List<CashShift> get history => _history;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  String? _successMessage;
  String? get successMessage => _successMessage;
  bool get hasActiveShift => _activeShift != null && _activeShift!.isOpen;

  Future<void> loadCurrentShift() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _activeShift = await gateway.fetchCurrentShift(branchId: branchId);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Gagal memuat status shift: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> openShift({
    int? startingCash,
    int? openingCash,
    String? notes,
    String? note,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final cash = startingCash ?? openingCash ?? 0;
      final n = notes ?? note;
      final shift = await gateway.openShift(
        startingCash: cash,
        notes: n,
        branchId: branchId,
      );
      _activeShift = shift;
      _errorMessage = null;
      _successMessage = 'Shift kasir berhasil dibuka.';
      return true;
    } catch (e) {
      _errorMessage = 'Gagal membuka shift: $e';
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<CashShift?> closeShift({
    required int actualCash,
    String? notes,
    String? note,
  }) async {
    if (_activeShift == null) {
      _errorMessage = 'Tidak ada shift aktif untuk ditutup.';
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final n = notes ?? note;
      final closed = await gateway.closeShift(
        shiftId: _activeShift!.id,
        actualCash: actualCash,
        notes: n,
      );
      _activeShift = null;
      _history.insert(0, closed);
      _errorMessage = null;
      _successMessage = 'Shift kasir berhasil ditutup dan direkonsiliasi.';
      return closed;
    } catch (e) {
      _errorMessage = 'Gagal menutup shift: $e';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    try {
      _history = await gateway.fetchShiftHistory(branchId: branchId, limit: 20);
      notifyListeners();
    } catch (_) {}
  }
}
