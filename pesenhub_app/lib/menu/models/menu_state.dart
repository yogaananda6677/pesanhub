enum MenuStatus { loading, success, empty, error }

/// MenuState represents presentation states of the menu catalog.
class MenuState {
  final MenuStatus status;
  final String? errorMessage;
  final bool isOffline;

  const MenuState({
    this.status = MenuStatus.loading,
    this.errorMessage,
    this.isOffline = false,
  });

  const MenuState.loading()
    : status = MenuStatus.loading,
      errorMessage = null,
      isOffline = false;

  const MenuState.success({this.isOffline = false})
    : status = MenuStatus.success,
      errorMessage = null;

  const MenuState.empty({this.isOffline = false})
    : status = MenuStatus.empty,
      errorMessage = null;

  const MenuState.error(String message, {this.isOffline = false})
    : status = MenuStatus.error,
      errorMessage = message;
}
