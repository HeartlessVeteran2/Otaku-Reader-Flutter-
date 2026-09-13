// Downloads the native Isar library the test suite loads.
//
// Run from a plain Dart VM (`dart run tool/fetch_isar_core.dart`), never from a
// test: `TestWidgetsFlutterBinding` stubs `HttpClient` out to return 400 for
// everything, so a widget test cannot download anything. CI runs this before
// `flutter test` so no suite has to.
import 'dart:io';

import '../test/helpers/isar_core_binary.dart';

Future<void> main() async {
  if (IsarCoreBinary.file.existsSync()) {
    stdout.writeln('IsarCore already present at ${IsarCoreBinary.file.path}');
    return;
  }
  stdout.writeln('Downloading ${IsarCoreBinary.downloadUrl}');
  await IsarCoreBinary.ensure();
  stdout.writeln(
    'IsarCore ready: ${IsarCoreBinary.file.path} '
    '(${IsarCoreBinary.file.lengthSync()} bytes)',
  );
}
