import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/key_value.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/preference/source_preference_store.dart';

/// Pins the rule the source system depends on most:
/// **the stored value wins, and the declared default is the fallback, read
/// lazily.**
///
/// Sources ship their working mirror or base-URL override as a declared default.
/// Seeding a copy of it at install — or, as upstream does, on first read —
/// freezes it, so when the source later ships a new mirror because the old
/// domain died, a user who never touched the setting keeps the dead one.
void main() {
  late Directory dir;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    dir = await Directory.systemTemp.createTemp('otaku_pref_test');
    db.isar = Isar.openSync(
      [KeyValueSchema],
      directory: dir.path,
      name: 'preftest',
      inspector: false,
    );
  });

  tearDownAll(() async {
    await db.isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  setUp(() => db.isar.writeTxnSync(() => db.isar.keyValues.clearSync()));

  List<SourcePreference> declaring(String mirror) => [
    SourcePreference(
      key: 'mirror',
      listPreference: ListPreference(
        title: 'Mirror',
        valueIndex: 0,
        entries: const ['Primary', 'Backup'],
        entryValues: [mirror, 'https://backup.example'],
      ),
    ),
    SourcePreference(
      key: 'nsfw',
      switchPreferenceCompat: SwitchPreferenceCompat(
        title: 'Show NSFW',
        value: false,
      ),
    ),
  ];

  test('falls back to the declared default when nothing is stored', () {
    expect(
      SourcePreferenceStore.value(1, 'mirror', declaring('https://a.test')),
      'https://a.test',
    );
    expect(
      SourcePreferenceStore.value(1, 'nsfw', declaring('https://a.test')),
      false,
    );
  });

  test('an updated declared default reaches a user who never set the value', () {
    // This is the whole point. The source ships a new mirror in an update; the
    // user never touched the setting, so they must follow it.
    expect(
      SourcePreferenceStore.value(1, 'mirror', declaring('https://old.test')),
      'https://old.test',
    );
    expect(
      SourcePreferenceStore.value(1, 'mirror', declaring('https://new.test')),
      'https://new.test',
    );
  });

  test('a stored value wins over the declared default', () {
    SourcePreferenceStore.setValue(1, 'mirror', 'https://user-chose.test');
    expect(
      SourcePreferenceStore.value(1, 'mirror', declaring('https://new.test')),
      'https://user-chose.test',
    );
  });

  test('reading a preference never writes one', () {
    SourcePreferenceStore.value(1, 'mirror', declaring('https://a.test'));
    // If the read seeded a row, the next declared default would be shadowed --
    // exactly the freeze this design exists to avoid.
    expect(db.isar.keyValues.countSync(), 0);
  });

  test('preferences are namespaced per source', () {
    SourcePreferenceStore.setValue(1, 'mirror', 'https://one.test');
    SourcePreferenceStore.setValue(2, 'mirror', 'https://two.test');
    expect(
      SourcePreferenceStore.value(1, 'mirror', const []),
      'https://one.test',
    );
    expect(
      SourcePreferenceStore.value(2, 'mirror', const []),
      'https://two.test',
    );
  });

  test('an unknown key with no declaration yields null, not a throw', () {
    expect(
      SourcePreferenceStore.value(1, 'nope', declaring('https://a.test')),
      isNull,
    );
  });

  test('a list default whose index is past the end falls back to the first', () {
    // A source that drops an option leaves stale indexes behind; answering with
    // the first entry beats throwing inside an extension call.
    final declared = [
      SourcePreference(
        key: 'mirror',
        listPreference: ListPreference(
          valueIndex: 7,
          entries: const ['Only'],
          entryValues: const ['https://only.test'],
        ),
      ),
    ];
    expect(
      SourcePreferenceStore.value(1, 'mirror', declared),
      'https://only.test',
    );
  });

  test('string values fall back to the caller default without persisting', () {
    expect(
      SourcePreferenceStore.stringValue(1, 'token', 'fallback'),
      'fallback',
    );
    expect(db.isar.keyValues.countSync(), 0);

    SourcePreferenceStore.setStringValue(1, 'token', 'stored');
    expect(SourcePreferenceStore.stringValue(1, 'token', 'fallback'), 'stored');
  });
}
