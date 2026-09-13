import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:otaku_reader/core/database/database.dart' as db;

/// Opens a throwaway Isar instance for a test suite, and tears it down.
///
/// Every suite that touches the database needs the same four steps, and four
/// hand-rolled copies is how they drift apart. It also centralises the native
/// library init: `initializeIsarCore` downloads `libisar.so` on first use, and
/// having each suite race to download it to the same path is what broke CI —
/// two suites crashed at finalisation with exit code -7 while every assertion
/// in them had passed.
class IsarTestEnv {
  IsarTestEnv._(this._directory);

  final Directory _directory;

  /// Opens [schemas] in a fresh temp directory and assigns the global `isar`,
  /// so code under test reaches it the same way it does in production.
  static Future<IsarTestEnv> open(
    String name,
    List<CollectionSchema<dynamic>> schemas,
  ) async {
    await Isar.initializeIsarCore(download: true);
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
