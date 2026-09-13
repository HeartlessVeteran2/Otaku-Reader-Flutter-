import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:otaku_reader/core/database/database.dart' as db;

import 'isar_core_binary.dart';

/// Opens a throwaway Isar instance for a test suite, and tears it down.
///
/// Every suite that touches the database needs the same four steps, and four
/// hand-rolled copies is how they drift apart. It also centralises the native
/// library init, which is the part that is easy to get wrong — see
/// [IsarCoreBinary] for why the library has to be fetched before the test
/// process starts rather than on first use.
class IsarTestEnv {
  IsarTestEnv._(this._directory);

  final Directory _directory;

  /// Opens [schemas] in a fresh temp directory and assigns the global `isar`,
  /// so code under test reaches it the same way it does in production.
  static Future<IsarTestEnv> open(
    String name,
    List<CollectionSchema<dynamic>> schemas,
  ) async {
    // One pinned path for every suite. Without `libraries`, Isar derives the
    // path from `Platform.script` -- a per-suite generated entrypoint under
    // `flutter test` -- so each suite looks somewhere different and only the
    // first one to download gets a working library.
    if (!IsarCoreBinary.file.existsSync()) {
      // `download: true` still works from a plain suite, and is what makes a
      // fresh checkout run without a setup step. It cannot work from a widget
      // test, so say so here rather than surfacing Isar's empty-reason-phrase
      // error, which says nothing about the cause or the cure.
      try {
        await IsarCoreBinary.ensure();
      } catch (e) {
        throw StateError(
          'The native Isar library is missing and could not be downloaded '
          '($e).\n'
          'Widget-test suites cannot download it: TestWidgetsFlutterBinding '
          'stubs HttpClient to return 400 for every request.\n'
          'Run `dart run tool/fetch_isar_core.dart` first.',
        );
      }
    }
    await Isar.initializeIsarCore(libraries: IsarCoreBinary.libraries);
    final directory = await Directory.systemTemp.createTemp('otaku_$name');
    db.isar = Isar.openSync(
      schemas,
      directory: directory.path,
      name: name,
      inspector: false,
    );
    return IsarTestEnv._(directory);
  }

  /// Empties every collection without reopening — cheaper than a fresh
  /// instance per test, and enough to isolate them from each other.
  void clear() => db.isar.writeTxnSync(() => db.isar.clearSync());

  Future<void> close() async {
    await db.isar.close(deleteFromDisk: true);
    if (_directory.existsSync()) _directory.deleteSync(recursive: true);
  }
}
