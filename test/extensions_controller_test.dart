import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

Source _source({
  required int id,
  String name = 'Example',
  String lang = 'en',
  String? code,
  String version = '1.0.0',
  String versionLast = '1.0.0',
  bool nsfw = false,
}) => Source()
  ..sourceId = id
  ..name = name
  ..lang = lang
  ..sourceCode = code
  ..version = version
  ..versionLast = versionLast
  ..isNsfw = nsfw
  ..sourceCodeUrl = 'https://example.test/$id.dart';

class _FakeExtensions implements ExtensionRepository {
  _FakeExtensions(this.rows);

  List<Source> rows;
  List<RefreshResult> refreshResults = const [];
  final List<String> calls = [];
  Object? failInstallWith;

  /// Completes when the test says so, to hold an install open.
  Completer<void>? gate;

  @override
  Future<List<Source>> listAll() async => rows;

  @override
  Future<Source> install(Source source) async {
    calls.add('install:${source.sourceId}');
    if (gate != null) await gate!.future;
    if (failInstallWith != null) throw failInstallWith!;
    source.sourceCode = 'CODE';
    source.version = source.versionLast;
    return source;
  }

  @override
  Future<Source> update(Source source) async {
    calls.add('update:${source.sourceId}');
    source.version = source.versionLast;
    return source;
  }

  @override
  Future<Source> uninstall(Source source) async {
    calls.add('uninstall:${source.sourceId}');
    source.sourceCode = null;
    return source;
  }

  @override
  Future<List<RefreshResult>> refreshAll() async {
    calls.add('refreshAll');
    return refreshResults;
  }

  @override
  Future<RefreshResult> refresh(String repoUrl) async =>
      RefreshResult(repoUrl: repoUrl);

  @override
  Future<RefreshResult> addRepo(ExtensionRepo repo) async {
    calls.add('addRepo:${repo.url}');
    return RefreshResult(repoUrl: repo.url);
  }

  @override
  Future<void> removeRepo(String url) async => calls.add('removeRepo:$url');

  @override
  Future<List<ExtensionRepo>> getRepos() async => const [];
  @override
  Future<Map<String, RepoHealth>> repoHealth() async => health;
  Map<String, RepoHealth> health = const {};
}

class _FakeSources implements SourceRepository {
  final List<int> evicted = [];

  @override
  void evict(int sourceId) => evicted.add(sourceId);
  @override
  void evictAll() {}
  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => const [];
  @override
  Future<SourceMethods> methodsFor(int sourceId) async =>
      throw UnimplementedError();
  @override
  Future<Source?> sourceById(int sourceId) async => null;
  @override
  Future<void> markUsed(int sourceId) async {}
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('extctl', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  Future<(ExtensionsController, _FakeExtensions, _FakeSources)> build(
    List<Source> rows,
  ) async {
    final extensions = _FakeExtensions(rows);
    final sources = _FakeSources();
    final controller = ExtensionsController(
      extensions: extensions,
      sources: sources,
      nsfw: NsfwPreference(),
    )..onInit();
    // onInit kicks off load() without awaiting; let it settle.
    await Future<void>.delayed(Duration.zero);
    return (controller, extensions, sources);
  }

  test(
    'tabs split the catalogue by installed state and pending updates',
    () async {
      final (c, _, _) = await build([
        _source(id: 1, name: 'Installed', code: 'X'),
        _source(id: 2, name: 'Available'),
        _source(id: 3, name: 'Stale', code: 'X', versionLast: '2.0.0'),
      ]);

      expect(c.visible(ExtensionTab.installed).map((s) => s.name), [
        'Installed',
        'Stale',
      ]);
      expect(c.visible(ExtensionTab.available).map((s) => s.name), [
        'Available',
      ]);
      expect(c.visible(ExtensionTab.updates).map((s) => s.name), ['Stale']);
      expect(c.updateCount, 1);
    },
  );

  test('an uninstalled source is never counted as having an update', () async {
    // hasUpdate is derived; a catalogue row whose advertised version moved on
    // must not show up as an update the user can apply to nothing.
    final (c, _, _) = await build([
      _source(id: 1, name: 'Never installed', versionLast: '9.0.0'),
    ]);

    expect(c.visible(ExtensionTab.updates), isEmpty);
    expect(c.updateCount, 0);
  });

  test('NSFW is hidden by default and the toggle persists', () async {
    final (c, _, _) = await build([
      _source(id: 1, name: 'Safe', code: 'X'),
      _source(id: 2, name: 'Adult', code: 'X', nsfw: true),
    ]);

    expect(c.visible(ExtensionTab.installed).map((s) => s.name), ['Safe']);

    c.toggleNsfw(true);
    expect(c.visible(ExtensionTab.installed).map((s) => s.name), [
      'Adult',
      'Safe',
    ]);
  });

  test('no stored language preference shows everything, not nothing', () async {
    // An empty set meaning "no languages" would give a first-run user an empty
    // catalogue that looks exactly like a failed fetch.
    final (c, _, _) = await build([
      _source(id: 1, name: 'English', lang: 'en', code: 'X'),
      _source(id: 2, name: 'French', lang: 'fr', code: 'X'),
    ]);

    expect(c.enabledLangs, isEmpty);
    expect(c.visible(ExtensionTab.installed), hasLength(2));
  });

  test("a language filter keeps 'all', the index's wildcard", () async {
    final (c, _, _) = await build([
      _source(id: 1, name: 'English', lang: 'en', code: 'X'),
      _source(id: 2, name: 'French', lang: 'fr', code: 'X'),
      _source(id: 3, name: 'Multi', lang: 'all', code: 'X'),
    ]);

    c.toggleLang('en');

    expect(c.visible(ExtensionTab.installed).map((s) => s.name), [
      'English',
      'Multi',
    ]);
  });

  test('search is case-insensitive and matches a substring', () async {
    final (c, _, _) = await build([
      _source(id: 1, name: 'MangaRead', code: 'X'),
      _source(id: 2, name: 'Raven Scans', code: 'X'),
    ]);

    c.setQuery('  raven ');
    expect(c.visible(ExtensionTab.installed).map((s) => s.name), [
      'Raven Scans',
    ]);
  });

  test('installing marks the row busy, evicts, and reloads', () async {
    final (c, ext, src) = await build([_source(id: 1)]);

    await c.install(ext.rows.single);

    expect(ext.calls, contains('install:1'));
    expect(src.evicted, [1], reason: 'a stale interpreter must not linger');
    expect(c.busy, isEmpty, reason: 'busy is cleared even on the happy path');
    expect(c.lastError.value, isNull);
  });

  test('updating routes through the same guard, eviction and reload', () async {
    final (c, ext, src) = await build([
      _source(id: 1, code: 'OLD', versionLast: '2.0.0'),
    ]);

    await c.updateSource(ext.rows.single);

    expect(ext.calls, contains('update:1'));
    expect(src.evicted, [1], reason: 'the old interpreter must not be served');
    expect(c.busy, isEmpty);
    expect(c.lastError.value, isNull);
  });

  test('uninstalling keeps the row listed and clears busy', () async {
    final (c, ext, src) = await build([_source(id: 1, code: 'X')]);

    await c.uninstall(ext.rows.single);

    expect(ext.calls, contains('uninstall:1'));
    expect(src.evicted, [1]);
    expect(c.busy, isEmpty);
    expect(c.visible(ExtensionTab.available).map((s) => s.name), [
      'Example',
    ], reason: 'still in the catalogue, re-installable');
  });

  test('a language still selected but gone from the index stays selectable', () async {
    // Otherwise the checkbox needed to turn the now-empty filter off is itself
    // hidden, and the user sees an empty list with no way out.
    final (c, _, _) = await build([_source(id: 1, lang: 'en', code: 'X')]);
    c.toggleLang('fr');

    expect(c.availableLangs, containsAll(['en', 'fr']));
  });

  test(
    'a second install of the same row while one is in flight is refused',
    () async {
      // Install is not idempotent from the user's point of view, and two
      // concurrent fetches for one row race on the same database write.
      final (c, ext, _) = await build([_source(id: 1)]);
      ext.gate = Completer<void>();

      final first = c.install(ext.rows.single);
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, contains(1));

      await c.install(ext.rows.single); // must return immediately
      expect(
        ext.calls.where((x) => x == 'install:1'),
        hasLength(1),
        reason: 'the second tap did not reach the repository',
      );

      ext.gate!.complete();
      await first;
      expect(c.busy, isEmpty);
    },
  );

  test('a failed install surfaces an error and clears busy', () async {
    final (c, ext, _) = await build([_source(id: 1, name: 'Broken')]);
    ext.failInstallWith = StateError('no code url');

    await c.install(ext.rows.single);

    expect(c.lastError.value, contains('Broken'));
    expect(c.busy, isEmpty, reason: 'a failure must not wedge the row');
  });

  test('a later success clears a stale error', () async {
    final (c, ext, _) = await build([_source(id: 1)]);
    ext.failInstallWith = StateError('transient');
    await c.install(ext.rows.single);
    expect(c.lastError.value, isNotNull);

    ext.failInstallWith = null;
    await c.install(ext.rows.single);

    expect(c.lastError.value, isNull);
  });

  test('one unreachable repo names that repo, several are counted', () async {
    final (c, ext, _) = await build([]);

    ext.refreshResults = [
      const RefreshResult(repoUrl: 'https://ok.test/index.json', added: 3),
      const RefreshResult(
        repoUrl: 'https://down.test/index.json',
        error: 'SocketException',
      ),
    ];
    await c.refreshRepos();
    expect(c.lastError.value, contains('down.test'));

    ext.refreshResults = [
      const RefreshResult(repoUrl: 'https://a.test/i.json', error: 'x'),
      const RefreshResult(repoUrl: 'https://b.test/i.json', error: 'y'),
    ];
    await c.refreshRepos();
    expect(c.lastError.value, contains('2 repositories'));

    ext.refreshResults = [
      const RefreshResult(repoUrl: 'https://ok.test/i.json'),
    ];
    await c.refreshRepos();
    expect(c.lastError.value, isNull);
  });

  test('a repo URL must be https', () async {
    final (c, ext, _) = await build([]);

    // An index names the scripts the app will fetch and interpret, so plaintext
    // lets anyone on the path choose what runs.
    expect(
      await c.addRepo('http://insecure.test/index.json'),
      contains('https'),
    );
    expect(await c.addRepo('not a url'), isNotNull);
    expect(await c.addRepo('  https://ok.test/index.json  '), isNull);
    expect(ext.calls, contains('addRepo:https://ok.test/index.json'));
  });

  test('availableLangs is derived from the catalogue, not hardcoded', () async {
    final (c, _, _) = await build([
      _source(id: 1, lang: 'en'),
      _source(id: 2, lang: 'fr'),
      _source(id: 3, lang: 'en'),
    ]);

    expect(c.availableLangs, ['en', 'fr']);
  });
}
