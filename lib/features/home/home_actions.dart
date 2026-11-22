import '../../core/api/api_models.dart';

/// User intents raised by [HomeView]; implemented by the Home screen.
abstract interface class HomeActions {
  void scan();
  void selectAction(PunchAction action);
  void cancelAction();
  void openHistory();
  void openSettings();
  void allowLocation();
  void openAppSettings();
  void openLocationSettings();
  void openNfcSettings();
  void logIn();
  void dismissResult();
  Future<void> refresh();

  /// Debug builds only: behaves as if the test card had been read.
  void simulateTap();
}
