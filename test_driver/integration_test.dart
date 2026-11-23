import 'package:integration_test/integration_test_driver.dart';

/// Driver for `flutter drive --no-dds
/// --driver=test_driver/integration_test.dart
/// --target=integration_test/perf_test.dart -d emulator-5554` (substitute the
/// suite and device as needed). `--no-dds` is required on Android emulators:
/// DDS blocks the VM-service connection `watchPerformance` uses.
///
/// Enables screenshot capture (onScreenshot) and avoids the `flutter test`
/// VM-service quirks on Android emulators.
Future<void> main() => integrationDriver();
