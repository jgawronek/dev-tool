import 'package:integration_test/integration_test.dart';

import '../test/ui/functionality_audit_test.dart' as audit;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  audit.sampleAuditTests(native: true);
}
