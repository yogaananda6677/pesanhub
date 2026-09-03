enum QueueStatus { loading, success, empty, error }

/// QueueState captures the loading/empty/error presentation state of the unified queue.
class QueueState {
  final QueueStatus status;
  final String? errorMessage;
  final bool isStale;
  final bool isOffline;

  const QueueState({
    this.status = QueueStatus.loading,
    this.errorMessage,
    this.isStale = false,
    this.isOffline = false,
  });

  const QueueState.loading()
    : status = QueueStatus.loading,
      errorMessage = null,
      isStale = false,
      isOffline = false;

  const QueueState.success({this.isStale = false, this.isOffline = false})
    : status = QueueStatus.success,
      errorMessage = null;

  const QueueState.empty({this.isStale = false, this.isOffline = false})
    : status = QueueStatus.empty,
      errorMessage = null;

  const QueueState.error(String message, {this.isOffline = false})
    : status = QueueStatus.error,
      errorMessage = message,
      isStale = false;
}
