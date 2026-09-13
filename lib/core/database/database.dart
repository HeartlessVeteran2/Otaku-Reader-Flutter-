import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:otaku_reader/core/database/key_value.dart';
import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/source/model/source.dart';

/// The single Isar instance. Assigned by [AppDatabase.init] before any
/// controller is constructed — controllers read persisted settings
/// synchronously during construction, so the order in `main()` is load-bearing.
late Isar isar;

/// The collections the app opens, in one place.
///
/// Exposed rather than private so a test can open exactly what production
/// opens. A collection that is annotated and generated but missing from this
/// list compiles and analyses clean, then throws the first time anything
/// touches it — `Source` shipped that way, because every test opened a
/// hand-picked subset instead of this list.
class AppDatabaseSchemas {
  const AppDatabaseSchemas._();

  static const all = [
    KeyValueSchema,
    MangaEntrySchema,
    CategoryEntrySchema,
    SourceSchema,
  ];
}

class AppDatabase {
  static const _name = 'OtakuReader';

  static Future<void> init() async {
    final dir = await _databaseDirectory();
    isar = _open(dir);
  }

  static Future<Directory> _databaseDirectory() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Opens the database, escalating through recovery steps rather than letting
  /// a corrupt file brick the app on launch.
  ///
  /// 1. Open normally.
  /// 2. A stale lock file survives a hard kill and makes every later open fail
  ///    with a file already in use. Deleting it is safe because the process
  ///    holding it is gone by definition. isar_community writes `.lck`, upstream
  ///    Isar writes `.lock`, so both names are cleared.
  /// 3. Only then treat the file as corrupt. Rename rather than delete: the
  ///    user's library is worth more than the disk space, and a rename is atomic
  ///    where a copy can fail halfway and leave two partial files.
  static Isar _open(Directory dir) {
    try {
      return _openSync(dir);
    } catch (_) {
      for (final suffix in const ['.lock', '.lck']) {
        final lock = File(p.join(dir.path, '$_name.isar$suffix'));
        if (lock.existsSync()) {
          try {
            lock.deleteSync();
          } catch (_) {
            // Nothing further to try; the rename below is the next escalation.
          }
        }
      }
      try {
        return _openSync(dir);
      } catch (_) {
        final db = File(p.join(dir.path, '$_name.isar'));
        if (db.existsSync()) {
          final stamp = DateTime.now().millisecondsSinceEpoch;
          db.renameSync(p.join(dir.path, '$_name.isar.corrupted_bak_$stamp'));
        }
        return _openSync(dir);
      }
    }
  }

  static Isar _openSync(Directory dir) => Isar.openSync(
    AppDatabaseSchemas.all,
    directory: dir.path,
    name: _name,
    inspector: false,
  );
}
