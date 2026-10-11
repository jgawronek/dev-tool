import 'package:integration_test/integration_test.dart';

import '../test/tools/formatter_options_test.dart' as matrix;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  matrix.formatterWidgetTests(native: true);
}
