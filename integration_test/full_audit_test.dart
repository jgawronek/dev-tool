import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// One native process avoids app bundle collisions between separate test files.
import 'all_samples_test.dart' as samples;
import 'formatter_options_test.dart' as formatters;
import 'image_clipboard_test.dart' as clipboard;
import 'app_tools_test.dart' as journeys;

void main() {
  // Keep native frame delivery live while the fixture explicitly brings its window forward.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  samples.main();
  formatters.main();
  clipboard.main();
  journeys.main();
}
