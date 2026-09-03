import 'operational_summary.dart';

enum DashboardStatus { loading, success, empty, error }

/// DashboardState represents the presentation state of the cashier dashboard.
class DashboardState {
  final DashboardStatus status;
  final OperationalSummary? summary;
  final String? errorMessage;

  const DashboardState({
    this.status = DashboardStatus.loading,
    this.summary,
    this.errorMessage,
  });

  const DashboardState.loading()
    : status = DashboardStatus.loading,
      summary = null,
      errorMessage = null;

  const DashboardState.success(OperationalSummary this.summary)
    : status = DashboardStatus.success,
      errorMessage = null;

  const DashboardState.empty({this.summary})
    : status = DashboardStatus.empty,
      errorMessage = null;

  const DashboardState.error(String message)
    : status = DashboardStatus.error,
      summary = null,
      errorMessage = message;
}
