import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';

/// Locates — and if necessary downloads — the native Isar library the tests run
/// against.
///
/// Isar's own `initializeIsarCore(download: true)` cannot be relied on here, and
/// the reason is structural rather than flaky: `TestWidgetsFlutterBinding`
/// replaces `HttpClient` with one that answers every request `400` and makes no
/// network call at all. So the download fails *by design* in any suite that uses
/// `testWidgets`, with the opaque message `Could not download IsarCore library:`
/// and an empty reason phrase. Whichever Isar-using suite happens to run first
/// decides whether the run passes.
///
/// Isar also resolves its download path from `Platform.script`, which under
/// `flutter test` is a generated per-suite entrypoint — so suites disagree about
/// where the library even is. Pinning one absolute path fixes both problems.
class IsarCoreBinary {
  const IsarCoreBinary._();

  /// One shared location, inside the build directory that is already ignored.
  static File get file =>
      File('${Directory.current.path}/.dart_tool/otaku/$_localName');

  /// What `initializeIsarCore` needs to skip its own path guessing.
  static Map<Abi, String> get libraries => {Abi.current(): file.path};

  static String get downloadUrl =>
      'https://binaries.isar-community.dev/${Isar.version}/$_remoteName';

  /// Downloads the library if it is not already present. Safe to call
  /// concurrently: the bytes land in a unique temp file and are moved into place
  /// with a single rename, so a reader never sees a half-written library.
  ///
  /// Must be called from a plain Dart VM or a plain `flutter test` suite — not
  /// from inside a widget test, for the reason in the class doc.
  static Future<void> ensure() async {
    if (file.existsSync() && file.lengthSync() > 0) return;
    file.parent.createSync(recursive: true);

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError(
          'Could not download IsarCore from $downloadUrl: '
          'HTTP ${response.statusCode} ${response.reasonPhrase}',
        );
      }
      final temp = File('${file.path}.${pid}_${DateTime.now().microsecond}');
      await response.pipe(temp.openWrite());
      temp.renameSync(file.path);
    } finally {
      client.close(force: true);
    }
  }

  static String get _localName {
    if (Platform.isMacOS) return 'libisar.dylib';
    if (Platform.isWindows) return 'isar.dll';
    return 'libisar.so';
  }

  static String get _remoteName {
    if (Platform.isMacOS) return 'libisar_macos.dylib';
    if (Platform.isWindows) return 'isar_windows_x64.dll';
    return 'libisar_linux_x64.so';
  }
}
