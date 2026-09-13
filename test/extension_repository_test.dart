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
  String? codeUrl = 'https://example.test/src/example.dart',
  String? additionalParams,
}) => {
  'id': id,
  'name': name,
  'baseUrl': 'https://example.test',
  'lang': 'en',
  'version': version,
  'itemType': itemType,
  'sourceCodeLanguage': 0,
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
}

/// Stands in for a transport failure without depending on dart:io's exact type.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketException: host unreachable';
}
