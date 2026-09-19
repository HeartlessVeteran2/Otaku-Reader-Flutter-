import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/repository/extension_repository_impl.dart';
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/source/model/source.dart';

import 'helpers/isar_test_env.dart';

const _repo = 'https://example.test/index.json';
const _otherRepo = 'https://other.test/index.json';

Map<String, dynamic> _entry({
  required int id,
  String name = 'Example',
  String version = '1.0.0',
  int itemType = 0,
  int sourceCodeLanguage = 0,
  String? codeUrl = 'https://example.test/src/example.dart',
  String? additionalParams,
}) => {
  'id': id,
  'name': name,
  'baseUrl': 'https://example.test',
  'lang': 'en',
  'version': version,
  'itemType': itemType,
  'sourceCodeLanguage': sourceCodeLanguage,
  'sourceCodeUrl': codeUrl,
  if (additionalParams != null) 'additionalParams': additionalParams,
};

/// Serves canned bodies per URL, so none of this touches the network.
class _Fetcher {
  _Fetcher(this.bodies);

  final Map<String, String> bodies;
  final List<String> requested = [];
  Object? failWith;

  Future<String> call(Uri url) async {
    requested.add(url.toString());
    if (failWith != null) throw failWith!;
    final body = bodies[url.toString()];
    if (body == null) throw StateError('no canned body for $url');
    return body;
  }
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('extrepo', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  ExtensionRepositoryImpl repoWith(_Fetcher fetcher) =>
      ExtensionRepositoryImpl(fetch: fetcher.call);

  test('a refresh adds the manga entries and skips the rest', () async {
    final fetcher = _Fetcher({
      _repo: jsonEncode([
        _entry(id: 1, name: 'Manga One'),
        _entry(id: 2, name: 'An Anime', itemType: 1),
        _entry(id: 3, name: 'Manga Two'),
      ]),
    });

    final result = await repoWith(fetcher).refresh(_repo);

    expect(result.isSuccess, isTrue);
    expect(result.added, 2);
    final stored = db.isar.sources.where().findAllSync();
    expect(stored.map((s) => s.name), containsAll(['Manga One', 'Manga Two']));
    expect(stored.map((s) => s.name), isNot(contains('An Anime')));
  });

  test('the id and additionalParams survive verbatim', () async {
    // additionalParams is what distinguishes one Madara site from the other 150
    // that share the script, so losing it collapses them into one broken source.
    final fetcher = _Fetcher({
      _repo: jsonEncode([
        _entry(id: 987654321, additionalParams: '{"sourceName":"zinmanga"}'),
      ]),
    });

    await repoWith(fetcher).refresh(_repo);

    final stored = db.isar.sources.where().findFirstSync()!;
    expect(stored.sourceId, 987654321);
    expect(stored.additionalParams, '{"sourceName":"zinmanga"}');
  });

  test('installing stores the code and clears the update flag', () async {
    const codeUrl = 'https://example.test/src/example.dart';
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1, version: '2.0.0')]),
      codeUrl: 'class DefaultExtension extends MProvider {}',
    });
    final repository = repoWith(fetcher);
    await repository.refresh(_repo);

    final before = db.isar.sources.where().findFirstSync()!;
    expect(before.isInstalled, isFalse);
    expect(before.hasUpdate, isFalse, reason: 'not installed, so not stale');

    await repository.install(before);

    final after = db.isar.sources.where().findFirstSync()!;
    expect(after.isInstalled, isTrue);
    expect(after.sourceCode, contains('MProvider'));
    expect(after.version, '2.0.0');
    expect(after.hasUpdate, isFalse);
  });

  test('a refresh does not uninstall an installed source', () async {
    // The whole risk in a refresh. Isar's unique-index `replace` would delete
    // the row and write the index's copy over it, silently uninstalling a
    // working extension and losing every user-owned field with it.
    const codeUrl = 'https://example.test/src/example.dart';
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1, version: '1.0.0')]),
      codeUrl: 'class DefaultExtension extends MProvider {}',
    });
    final repository = repoWith(fetcher);
    await repository.refresh(_repo);
    await repository.install(db.isar.sources.where().findFirstSync()!);

    // The index now advertises a newer version and a renamed source.
    fetcher.bodies[_repo] = jsonEncode([
      _entry(id: 1, name: 'Renamed', version: '3.0.0'),
    ]);
    final result = await repository.refresh(_repo);

    expect(result.updated, 1);
    expect(result.removed, 0);
    final after = db.isar.sources.where().findFirstSync()!;
    expect(after.sourceCode, isNotNull, reason: 'still installed');
    expect(after.version, '1.0.0', reason: 'the installed code is still v1');
    expect(after.versionLast, '3.0.0', reason: 'the index moved on');
    expect(after.hasUpdate, isTrue, reason: 'so an update is offered');
    expect(after.name, 'Renamed', reason: 'index-owned fields do update');
  });

  test('user-owned flags survive a refresh', () async {
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1)]),
    });
    final repository = repoWith(fetcher);
    await repository.refresh(_repo);

    final pinned = db.isar.sources.where().findFirstSync()!;
    db.isar.writeTxnSync(() {
      pinned
        ..isPinned = true
        ..isActive = false;
      db.isar.sources.putSync(pinned);
    });

    await repository.refresh(_repo);

    final after = db.isar.sources.where().findFirstSync()!;
    expect(after.isPinned, isTrue);
    expect(after.isActive, isFalse);
  });

  test(
    'a source dropped from the index goes only if it is not installed',
    () async {
      const codeUrl = 'https://example.test/src/example.dart';
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1), _entry(id: 2, name: 'Keeper')]),
        codeUrl: 'class DefaultExtension extends MProvider {}',
      });
      final repository = repoWith(fetcher);
      await repository.refresh(_repo);

      final keeper = db.isar.sources
          .filter()
          .sourceIdEqualTo(2)
          .findFirstSync()!;
      await repository.install(keeper);

      // Both vanish from upstream.
      fetcher.bodies[_repo] = jsonEncode(<Map<String, dynamic>>[]);
      final result = await repository.refresh(_repo);

      expect(result.removed, 1, reason: 'only the uninstalled one');
      final remaining = db.isar.sources.where().findAllSync();
      expect(remaining.map((s) => s.sourceId), [2]);
      expect(
        remaining.single.isInstalled,
        isTrue,
        reason: 'library rows point at it; deleting it strands them',
      );
    },
  );

  test('a failed fetch changes nothing', () async {
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1)]),
    });
    final repository = repoWith(fetcher);
    await repository.refresh(_repo);
    expect(db.isar.sources.countSync(), 1);

    fetcher.failWith = const SocketExceptionStub();
    final result = await repository.refresh(_repo);

    expect(result.isSuccess, isFalse);
    expect(result.error, isNotNull);
    expect(
      db.isar.sources.countSync(),
      1,
      reason: 'a flaky network must not empty the extension list',
    );
  });

  test('an index that is not a list is an error, not a wipe', () async {
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1)]),
    });
    final repository = repoWith(fetcher);
    await repository.refresh(_repo);

    fetcher.bodies[_repo] = jsonEncode({'error': 'nope'});
    final result = await repository.refresh(_repo);

    expect(result.isSuccess, isFalse);
    expect(db.isar.sources.countSync(), 1);
  });

  test('one malformed entry does not cost the whole index', () async {
    final fetcher = _Fetcher({
      _repo: jsonEncode([
        _entry(id: 1, name: 'Good'),
        {'name': 'no id at all'},
        _entry(id: 3, name: 'Also good'),
      ]),
    });

    final result = await repoWith(fetcher).refresh(_repo);

    expect(result.added, 2);
    expect(
      db.isar.sources.where().findAllSync().map((s) => s.name),
      containsAll(['Good', 'Also good']),
    );
  });

  test('removing a repo takes only its own sources', () async {
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1, name: 'From repo one')]),
      _otherRepo: jsonEncode([_entry(id: 2, name: 'From repo two')]),
    });
    final repository = repoWith(fetcher);
    await repository.addRepo(const ExtensionRepo(url: _repo));
    await repository.addRepo(const ExtensionRepo(url: _otherRepo));
    expect(db.isar.sources.countSync(), 2);

    await repository.removeRepo(_repo);

    expect(db.isar.sources.where().findAllSync().map((s) => s.name), [
      'From repo two',
    ]);
    // The built-in default is still there: the first addRepo materialised the
    // seed, which is what keeps it from vanishing the moment a user adds one of
    // their own. Removing a repo must not take the others with it.
    expect((await repository.getRepos()).map((r) => r.url), [
      ExtensionRepositoryImpl.defaultRepoUrl,
      _otherRepo,
    ]);
  });

  test(
    'a fresh install seeds the default repo, an emptied one stays empty',
    () async {
      final repository = repoWith(_Fetcher({}));

      expect(
        (await repository.getRepos()).single.url,
        ExtensionRepositoryImpl.defaultRepoUrl,
        reason: 'nothing stored means seed the default',
      );

      SourceKeys.repoUrls.set<List<dynamic>>(const []);

      expect(
        await repository.getRepos(),
        isEmpty,
        reason: 'a user who removed every repo must not have one resurrected',
      );
    },
  );

  test('a JavaScript entry is not listed at all', () async {
    // This app interprets Dart. Listing a JavaScript entry offers an install
    // that leads to a source which cannot open, and the failure reads as a
    // broken extension rather than as an unsupported one. The Dart half is the
    // ecosystem — 249 index entries across ~245 sites, against 18 distinct
    // JavaScript scripts (CLAUDE.md).
    final fetcher = _Fetcher({
      _repo: jsonEncode([
        _entry(id: 1, name: 'Dart source'),
        _entry(id: 2, name: 'JS source', sourceCodeLanguage: 1),
      ]),
    });
    final repository = repoWith(fetcher);

    final result = await repository.addRepo(const ExtensionRepo(url: _repo));

    expect(result.added, 1, reason: 'the JS entry is not counted either');
    expect(db.isar.sources.where().findAllSync().map((s) => s.name), [
      'Dart source',
    ]);
  });

  test('a JavaScript row stored by an older build is cleaned up', () async {
    // The filter is new, so a database written before it can hold JS rows. The
    // stale-removal path has to take them, or they stay listed forever.
    final repository = repoWith(
      _Fetcher({
        _repo: jsonEncode([_entry(id: 1, name: 'Dart source')]),
      }),
    );
    db.isar.writeTxnSync(
      () => db.isar.sources.putSync(
        Source()
          ..sourceId = 99
          ..name = 'Left over from an older build'
          ..lang = 'en'
          ..repoUrl = _repo
          ..sourceCodeLanguage = SourceCodeLanguage.javascript,
      ),
    );

    await repository.addRepo(const ExtensionRepo(url: _repo));

    expect(db.isar.sources.where().findAllSync().map((s) => s.name), [
      'Dart source',
    ]);
  });

  test('removing a repo keeps its installed sources, detached', () async {
    // Deleting an installed row makes every library entry pointing at it fail
    // with "No source with id ...", and the user's progress, favourites and
    // downloads all hang off that id. Detaching keeps it working and only
    // stops updates, which is what removing a repo should mean.
    final fetcher = _Fetcher({
      _repo: jsonEncode([
        _entry(id: 1, name: 'Installed'),
        _entry(id: 2, name: 'Never installed'),
      ]),
      'https://example.test/src/example.dart': 'class DefaultExtension {}',
    });
    final repository = repoWith(fetcher);
    await repository.addRepo(const ExtensionRepo(url: _repo));
    final installed = db.isar.sources
        .filter()
        .sourceIdEqualTo(1)
        .findFirstSync()!;
    await repository.install(installed);

    await repository.removeRepo(_repo);

    final rows = db.isar.sources.where().findAllSync();
    expect(rows.map((s) => s.name), ['Installed']);
    expect(rows.single.isInstalled, isTrue, reason: 'it still works');
    expect(
      rows.single.repoUrl,
      isNull,
      reason: 'detached, so it stops receiving updates',
    );
  });

  test('two removals at once do not resurrect one another', () async {
    // Both calls read the stored list, filter it, and write the whole thing
    // back. Interleaved -- two quick taps is enough -- the second write is
    // built from a list read before the first write landed, so the first
    // removal is undone and a repository the user deleted comes back.
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1)]),
      _otherRepo: jsonEncode([_entry(id: 2)]),
    });
    final repository = repoWith(fetcher);
    await repository.addRepo(const ExtensionRepo(url: _repo));
    await repository.addRepo(const ExtensionRepo(url: _otherRepo));

    await Future.wait([
      repository.removeRepo(_repo),
      repository.removeRepo(_otherRepo),
    ]);

    expect((await repository.getRepos()).map((r) => r.url), [
      ExtensionRepositoryImpl.defaultRepoUrl,
    ]);
    expect(db.isar.sources.countSync(), 0);
  });

  test('adding a repo twice does not duplicate it', () async {
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1)]),
    });
    final repository = repoWith(fetcher);

    await repository.addRepo(const ExtensionRepo(url: _repo));
    await repository.addRepo(const ExtensionRepo(url: _repo));

    expect(
      (await repository.getRepos()).where((r) => r.url == _repo),
      hasLength(1),
    );
    expect(db.isar.sources.countSync(), 1);
  });

  test('uninstalling keeps the row browsable', () async {
    const codeUrl = 'https://example.test/src/example.dart';
    final fetcher = _Fetcher({
      _repo: jsonEncode([_entry(id: 1, version: '1.0.0')]),
      codeUrl: 'class DefaultExtension extends MProvider {}',
    });
    final repository = repoWith(fetcher);
    await repository.refresh(_repo);
    await repository.install(db.isar.sources.where().findFirstSync()!);

    await repository.uninstall(db.isar.sources.where().findFirstSync()!);

    final after = db.isar.sources.where().findFirstSync()!;
    expect(after.isInstalled, isFalse);
    expect(after.name, isNotEmpty, reason: 'still listed, still installable');
    expect(
      after.version,
      '0.0.1',
      reason: 'so a reinstall is not mistaken for up to date',
    );
  });

  test(
    'an entry with no code URL is refused rather than half-installed',
    () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1, codeUrl: null)]),
      });
      final repository = repoWith(fetcher);
      await repository.refresh(_repo);

      await expectLater(
        repository.install(db.isar.sources.where().findFirstSync()!),
        throwsStateError,
      );
      expect(db.isar.sources.where().findFirstSync()!.isInstalled, isFalse);
    },
  );

  group('repo health', () {
    // The record exists to answer "which of my repos is failing?". A refresh
    // that fails deliberately leaves the known sources in place, so without
    // this a dead repo is indistinguishable from a healthy one that simply has
    // nothing new to offer.

    test('a successful refresh records a success', () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1)]),
      });
      final repository = repoWith(fetcher);
      await repository.addRepo(const ExtensionRepo(url: _repo));

      final health = await repository.repoHealth();
      expect(health.keys, [_repo]);
      expect(health[_repo]!.isSuccess, isTrue);
      expect(health[_repo]!.error, isNull);
    });

    // Each of `_refresh`'s three exits gets its own case, because the wrapper
    // exists so that none of them can skip the record -- and a failure that
    // goes unrecorded is the single case this whole feature is for.
    test('a transport failure is recorded, with its reason', () async {
      final fetcher = _Fetcher({})..failWith = const SocketExceptionStub();
      final repository = repoWith(fetcher);
      await repository.addRepo(const ExtensionRepo(url: _repo));

      final health = await repository.repoHealth();
      expect(health[_repo]!.isSuccess, isFalse);
      expect(health[_repo]!.error, contains('host unreachable'));
    });

    test('an index that is not a list is recorded as a failure', () async {
      final fetcher = _Fetcher({_repo: '{"not": "a list"}'});
      final repository = repoWith(fetcher);
      await repository.addRepo(const ExtensionRepo(url: _repo));

      final health = await repository.repoHealth();
      expect(health[_repo]!.isSuccess, isFalse);
      expect(health[_repo]!.error, contains('not a JSON list'));
    });

    test('a later success clears an earlier failure', () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1)]),
      })..failWith = const SocketExceptionStub();
      final repository = repoWith(fetcher);
      await repository.addRepo(const ExtensionRepo(url: _repo));
      expect((await repository.repoHealth())[_repo]!.isSuccess, isFalse);

      fetcher.failWith = null;
      await repository.refresh(_repo);
      final health = await repository.repoHealth();
      expect(health[_repo]!.isSuccess, isTrue);
      expect(health[_repo]!.error, isNull);
    });

    // Never-checked is a third state. A repo carrying no record must not
    // borrow either of the other two: reporting a repo nobody has refreshed as
    // *failing* is a claim about a request that was never made.
    test('a repo that has never been refreshed has no record', () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1)]),
      });
      final repository = repoWith(fetcher);
      SourceKeys.repoUrls.set<List<dynamic>>([
        const ExtensionRepo(url: _repo).toJson(),
        const ExtensionRepo(url: _otherRepo).toJson(),
      ]);
      await repository.refresh(_repo);

      final health = await repository.repoHealth();
      expect(health.containsKey(_repo), isTrue);
      expect(health.containsKey(_otherRepo), isFalse);
    });

    test('removing a repo forgets its record', () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1)]),
      });
      final repository = repoWith(fetcher);
      await repository.addRepo(const ExtensionRepo(url: _repo));
      expect(await repository.repoHealth(), isNotEmpty);

      await repository.removeRepo(_repo);
      expect(await repository.repoHealth(), isEmpty);

      // The stored row is gone, not merely filtered out of the answer --
      // otherwise re-adding the same URL shows its previous life's outcome
      // until a fresh refresh lands.
      final raw = SourceKeys.repoHealth.get<Map<String, dynamic>?>();
      expect(raw == null || !raw.containsKey(_repo), isTrue);
    });

    test('a record never outlives the repo it describes', () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1)]),
      });
      final repository = repoWith(fetcher);
      await repository.addRepo(const ExtensionRepo(url: _repo));
      // A row that outlived its repo: a removal that raced a refresh, or a
      // build whose removal predates the pruning.
      SourceKeys.repoUrls.set<List<dynamic>>([]);

      expect(await repository.repoHealth(), isEmpty);
    });

    // Both refreshes read the whole map, change one entry and write it back.
    // Nothing serialises them — nothing needs to, because that read-modify-write
    // is synchronous and so cannot be interleaved on Dart's one thread.
    //
    // This test is the guard on that property rather than on a lock. Proven by
    // putting a single `await` between the read and the write: this is the test
    // that fails, and only this one.
    test('two refreshes at once do not lose one another', () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1)]),
        _otherRepo: jsonEncode([_entry(id: 2)]),
      });
      final repository = repoWith(fetcher);
      SourceKeys.repoUrls.set<List<dynamic>>([
        const ExtensionRepo(url: _repo).toJson(),
        const ExtensionRepo(url: _otherRepo).toJson(),
      ]);

      await Future.wait([
        repository.refresh(_repo),
        repository.refresh(_otherRepo),
      ]);

      final health = await repository.repoHealth();
      expect(health.keys.toSet(), {_repo, _otherRepo});
    });

    test('a corrupt stored row is dropped, not thrown', () async {
      final fetcher = _Fetcher({
        _repo: jsonEncode([_entry(id: 1)]),
      });
      final repository = repoWith(fetcher);
      SourceKeys.repoUrls.set<List<dynamic>>([
        const ExtensionRepo(url: _repo).toJson(),
      ]);
      // No `checkedAt`: a row some other build wrote.
      SourceKeys.repoHealth.set<Map<String, dynamic>>({
        _repo: {'error': 'whatever'},
      });

      expect(await repository.repoHealth(), isEmpty);
    });
  });
}

/// Stands in for a transport failure without depending on dart:io's exact type.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketException: host unreachable';
}
