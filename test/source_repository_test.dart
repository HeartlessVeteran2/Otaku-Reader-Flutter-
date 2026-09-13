import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/repository/source_repository_impl.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

/// Stands in for a real runtime, recording the code it was built from so a test
/// can tell a rebuilt instance from a cached one.
class _FakeRuntime implements SourceMethods {
  _FakeRuntime(this.source) : builtFromCode = source.sourceCode;

  @override
  final Source source;
  final String? builtFromCode;
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  @override
  String get sourceBaseUrl => source.baseUrl ?? '';
  @override
  bool get supportsLatest => true;
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MPages> getPopular(int page) async =>
      MPages(list: [], hasNextPage: false);
  @override
  Future<MPages> getLatestUpdates(int page) async =>
      MPages(list: [], hasNextPage: false);
  @override
  Future<MPages> search(String q, int page, FilterList f) async =>
      MPages(list: [], hasNextPage: false);
  @override
  Future<MManga> getDetail(String url) async => MManga();
  @override
  Future<List<PageUrl>> getPageList(String url) async => const [];
  @override
  FilterList getFilterList() => FilterList([]);
  @override
  List<SourcePreference> getSourcePreferences() => const [];
}

Source _source({
  required int id,
  String name = 'Example',
  String lang = 'en',
  String? code = 'class DefaultExtension extends MProvider {}',
  String version = '1.0.0',
  bool nsfw = false,
}) => Source()
  ..sourceId = id
  ..name = name
  ..lang = lang
  ..baseUrl = 'https://example.test'
  ..sourceCode = code
  ..version = version
  ..versionLast = version
  ..isNsfw = nsfw;

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('srcrepo', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final built = <_FakeRuntime>[];
  SourceRepositoryImpl repository() {
    built.clear();
    return SourceRepositoryImpl(
      runtimeFactory: (s) {
        final r = _FakeRuntime(s);
        built.add(r);
        return r;
      },
    );
  }

  void put(Source s) => db.isar.writeTxnSync(() => db.isar.sources.putSync(s));

  test('only installed sources are listed', () async {
    put(_source(id: 1, name: 'Installed'));
    put(_source(id: 2, name: 'Catalogue only', code: null));

    final listed = await repository().installedSources();

    expect(listed.map((s) => s.name), ['Installed']);
  });

  test('NSFW sources are excluded unless asked for', () async {
    put(_source(id: 1, name: 'Safe'));
    put(_source(id: 2, name: 'Adult', nsfw: true));

    final repo = repository();
    expect((await repo.installedSources()).map((s) => s.name), ['Safe']);
    expect(
      (await repo.installedSources(includeNsfw: true)).map((s) => s.name),
      containsAll(['Safe', 'Adult']),
    );
  });

  test(
    "a language filter keeps 'all', which is the index's wildcard",
    () async {
      put(_source(id: 1, name: 'English', lang: 'en'));
      put(_source(id: 2, name: 'French', lang: 'fr'));
      put(_source(id: 3, name: 'Multi', lang: 'all'));

      final listed = await repository().installedSources(langs: {'en'});

      expect(
        listed.map((s) => s.name),
        containsAll(['English', 'Multi']),
        reason: "'all' sources serve every language",
      );
      expect(listed.map((s) => s.name), isNot(contains('French')));
    },
  );

  test('a runtime is built once and reused', () async {
    put(_source(id: 1));
    final repo = repository();

    final first = await repo.methodsFor(1);
    final second = await repo.methodsFor(1);

    expect(identical(first, second), isTrue);
    expect(built, hasLength(1));
  });

  test('updated code rebuilds the runtime rather than serving the old one', () async {
    // The failure this guards is silent: an updated extension keeps running its
    // old code while the UI reports it as up to date, and the user blames the
    // source.
    put(_source(id: 1, code: 'OLD CODE', version: '1.0.0'));
    final repo = repository();
    final first = await repo.methodsFor(1) as _FakeRuntime;
    expect(first.builtFromCode, 'OLD CODE');

    final row = db.isar.sources.filter().sourceIdEqualTo(1).findFirstSync()!;
    db.isar.writeTxnSync(() {
      row
        ..sourceCode = 'NEW CODE'
        ..version = '2.0.0';
      db.isar.sources.putSync(row);
    });

    final second = await repo.methodsFor(1) as _FakeRuntime;

    expect(second.builtFromCode, 'NEW CODE');
    expect(identical(first, second), isFalse);
    expect(
      first.disposed,
      isFalse,
      reason:
          'a superseded runtime is dropped, not disposed -- a browse or '
          'reader screen may still be awaiting a call on it, and disposing '
          'nulls the interpreter out from under it',
    );
  });

  test('code republished without a version bump still rebuilds', () async {
    // Version alone would miss this, and a source author re-cutting the same
    // version is ordinary rather than exotic.
    put(_source(id: 1, code: 'FIRST', version: '1.0.0'));
    final repo = repository();
    await repo.methodsFor(1);

    final row = db.isar.sources.filter().sourceIdEqualTo(1).findFirstSync()!;
    db.isar.writeTxnSync(() {
      row.sourceCode = 'OTHER';
      db.isar.sources.putSync(row);
    });

    final second = await repo.methodsFor(1) as _FakeRuntime;
    expect(second.builtFromCode, 'OTHER');
  });

  test('unchanged code does not rebuild, even across a row rewrite', () async {
    put(_source(id: 1));
    final repo = repository();
    final first = await repo.methodsFor(1);

    // A refresh rewrites the row without touching the code.
    final row = db.isar.sources.filter().sourceIdEqualTo(1).findFirstSync()!;
    db.isar.writeTxnSync(() {
      row.name = 'Renamed upstream';
      db.isar.sources.putSync(row);
    });

    expect(identical(await repo.methodsFor(1), first), isTrue);
    expect(built, hasLength(1));
  });

  test('evict drops the runtime without disposing it', () async {
    // Disposing would kill a request another screen has in flight on this
    // runtime -- exactly what happens when the user updates a source from the
    // extensions screen while browsing it elsewhere.
    put(_source(id: 1));
    final repo = repository();
    final first = await repo.methodsFor(1) as _FakeRuntime;

    repo.evict(1);

    expect(first.disposed, isFalse, reason: 'still usable by whoever holds it');
    expect(
      identical(await repo.methodsFor(1), first),
      isFalse,
      reason: 'but the cache no longer serves it',
    );
  });

  test('a changed base URL rebuilds, even with identical code', () async {
    // toMSource() hands baseUrl, apiUrl and additionalParams to the extension
    // at construction, so the source's own fields are part of a runtime's
    // identity -- not just the script text.
    put(_source(id: 1, code: 'SAME CODE'));
    final repo = repository();
    final first = await repo.methodsFor(1);

    final row = db.isar.sources.filter().sourceIdEqualTo(1).findFirstSync()!;
    db.isar.writeTxnSync(() {
      row.baseUrl = 'https://moved.example';
      db.isar.sources.putSync(row);
    });

    expect(identical(await repo.methodsFor(1), first), isFalse);
  });

  test('changed additionalParams rebuilds, even with identical code', () async {
    // additionalParams is what distinguishes one Madara site from the other 150
    // sharing that script.
    put(_source(id: 1, code: 'SAME CODE'));
    final repo = repository();
    final first = await repo.methodsFor(1);

    final row = db.isar.sources.filter().sourceIdEqualTo(1).findFirstSync()!;
    db.isar.writeTxnSync(() {
      row.additionalParams = '{"sourceName":"other"}';
      db.isar.sources.putSync(row);
    });

    expect(identical(await repo.methodsFor(1), first), isFalse);
  });

  test('evictAll does dispose, because it is teardown', () async {
    put(_source(id: 1));
    put(_source(id: 2, name: 'Second'));
    final repo = repository();
    final a = await repo.methodsFor(1) as _FakeRuntime;
    final b = await repo.methodsFor(2) as _FakeRuntime;

    repo.evictAll();

    expect([a.disposed, b.disposed], [true, true]);
  });

  test(
    'an absent or uninstalled source is refused, not returned null',
    () async {
      put(_source(id: 2, code: null));
      final repo = repository();

      await expectLater(repo.methodsFor(1), throwsStateError);
      await expectLater(repo.methodsFor(2), throwsStateError);
    },
  );

  test('markUsed stamps the row and tolerates an unknown id', () async {
    put(_source(id: 1));
    final repo = repository();
    expect(
      db.isar.sources.filter().sourceIdEqualTo(1).findFirstSync()!.lastUsed,
      isNull,
    );

    await repo.markUsed(1);
    await repo.markUsed(999); // must not throw

    expect(
      db.isar.sources.filter().sourceIdEqualTo(1).findFirstSync()!.lastUsed,
      isNotNull,
    );
  });
}
