/// Driver half of `flutter drive`. The test itself is
/// `integration_test/keychain_persistence_test.dart`, which is where the
/// phases and the commands to run them are documented.
library;

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
