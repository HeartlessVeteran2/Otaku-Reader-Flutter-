import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/key_value.dart';
import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/source/model/m_status.dart';
import 'package:otaku_reader/source/model/source.dart';

import 'helpers/isar_test_env.dart';

/// Opens the **production** schema list and writes one row per collection.
///
/// Every other test opens a hand-picked subset, which cannot see the failure
/// this guards: a collection that is `@collection`-annotated and generated but
/// never added to [AppDatabase.schemas] compiles, passes analysis, and throws
/// only when something first touches it at runtime. `Source` shipped that way.
///
/// Round-tripping a row per collection is the assertion — merely opening the
/// database would not prove the collection is usable.
void main() {
  late IsarTestEnv env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('schema', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env.close());

  test('every generated collection is registered and usable', () {
    // If a schema is missing from the list, the matching accessor throws here
    // rather than in front of a user.
    db.isar.writeTxnSync(() {
      db.isar.keyValues.putSync(
        KeyValue()
          ..key = 'k'
          ..value = '{"val":1}',
      );
      db.isar.mangaEntrys.putSync(
        MangaEntry()
          ..sourceId = 'src'
          ..url = '/manga/1'
          ..title = 'Title',
      );
      db.isar.categoryEntrys.putSync(CategoryEntry()..name = 'Default');
      db.isar.sources.putSync(
        Source()
          ..sourceId = 1
          ..name = 'Test Source'
          ..lang = 'en',
      );
    });

    expect(db.isar.keyValues.countSync(), 1);
    expect(db.isar.mangaEntrys.countSync(), 1);
    expect(db.isar.categoryEntrys.countSync(), 1);
    expect(db.isar.sources.countSync(), 1);
  });

  test('a Source round-trips through the database', () {
    // Source is the collection that was missing, so it gets the closer look:
    // the fields the runtime actually reads must survive a write and read.
    final source = Source()
      ..sourceId = 42
      ..name = 'Madara Site'
      ..lang = 'en'
      ..baseUrl = 'https://example.com'
      ..additionalParams = '?lang=en'
      ..sourceCodeLanguage = SourceCodeLanguage.dart
      ..sourceCode = 'class X {}';

    db.isar.writeTxnSync(() => db.isar.sources.putSync(source));

    final read = db.isar.sources.filter().sourceIdEqualTo(42).findFirstSync();
    expect(read, isNotNull);
    expect(read!.name, 'Madara Site');
    expect(read.sourceCodeLanguage, SourceCodeLanguage.dart);
    expect(read.itemType, ItemType.manga);
    // additionalParams is what distinguishes one multisrc site from the other
    // 150 sharing its script, so losing it in storage would collapse them.
    expect(read.additionalParams, '?lang=en');
    expect(read.isInstalled, isTrue);
  });

  test('a new manga entry is of unknown status, not "publishing finished"', () {
    // The default is an index into Status; getting it wrong silently marks every
    // entry the user adds as finished.
    final entry = MangaEntry()
      ..sourceId = 'src'
      ..url = '/manga/2'
      ..title = 'Fresh';
    expect(Status.values[entry.status], Status.unknown);
  });
}
