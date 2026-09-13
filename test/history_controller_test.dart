import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/history/controllers/history_controller.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

const _sourceId = 7;

class _NoSources implements SourceRepository {
  @override
  Future<Source?> sourceById(int id) async => null;
  @override
  Future<SourceMethods> methodsFor(int id) async => throw UnimplementedError();
  @override
  Future<void> markUsed(int id) async {}
  @override
  void evict(int id) {}
  @override
  void evictAll() {}
  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => const [];
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('history', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  /// Stores a manga and marks some of its chapters read, which is what puts a
  /// timestamp on them.
  Future<void> seed({
    required String url,
    required String title,
    required List<String> chapters,
    required List<String> read,
    bool favourite = false,
  }) async {
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: url,
      manga: MManga(
        name: title,
        chapters: [
          for (final c in chapters) MChapter(url: c, name: 'Chapter $c'),
        ],
      ),
    );
    if (favourite) await library.toggleFavorite(_sourceId, url);
    for (final c in read) {
      await library.setChapterRead(_sourceId, url, c, true);
    }
  }

  Future<HistoryController> build() async {
    final c = HistoryController(library: library, sources: _NoSources())
      ..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('history covers entries that were never added to the library', () async {
    // A chapter read from a source and never favourited is exactly the thing a
    // user comes back looking for.
    await seed(
      url: '/not-followed',
      title: 'Merely opened',
      chapters: ['/c-1'],
      read: ['/c-1'],
    );

    final c = await build();

    expect(c.visible.map((e) => e.entry.displayTitle), ['Merely opened']);
  });

  test('unread chapters are not in the timeline', () async {
    await seed(
      url: '/m',
      title: 'Example',
      chapters: ['/c-1', '/c-2'],
      read: ['/c-1'],
    );

    final c = await build();

    expect(c.visible.map((e) => e.chapter.url), ['/c-1']);
  });

  test('newest first', () async {
    await seed(url: '/m', title: 'Example', chapters: ['/c-1'], read: ['/c-1']);
    await seed(url: '/n', title: 'Later', chapters: ['/c-9'], read: ['/c-9']);

    final c = await build();

    // Same millisecond is possible on a fast machine, so this asserts the
    // ordering is non-increasing rather than a specific pair of rows.
    final times = c.visible.map((e) => e.readAt).toList();
    for (var i = 1; i < times.length; i++) {
      expect(times[i].isAfter(times[i - 1]), isFalse);
    }
    expect(times, hasLength(2));
  });

  test('a removal hides the row immediately and undo brings it back', () async {
    await seed(url: '/m', title: 'Example', chapters: ['/c-1'], read: ['/c-1']);
    final c = await build();
    final row = c.visible.single;

    c.remove([row]);
    expect(c.visible, isEmpty, reason: 'hidden before the window closes');

    expect(c.undo(), isTrue);
    expect(c.visible.map((e) => e.chapter.url), ['/c-1']);
  });

  test('undo after the batch has committed is refused, not silent', () async {
    // The snackbar outlives the window -- its action stays tappable until the
    // bar is dismissed -- so the controller has to be able to say "too late"
    // rather than quietly doing nothing or reinstating the wrong batch.
    await seed(url: '/m', title: 'Example', chapters: ['/c-1'], read: ['/c-1']);
    final c = await build();

    c.remove([c.visible.single]);
    await c.clearAll();

    expect(c.undo(), isFalse);
  });

  test(
    'a second removal commits the first rather than stealing its undo',
    () async {
      await seed(
        url: '/m',
        title: 'Example',
        chapters: ['/c-1', '/c-2'],
        read: ['/c-1', '/c-2'],
      );
      final c = await build();
      final first = c.visible.firstWhere((e) => e.chapter.url == '/c-1');
      final second = c.visible.firstWhere((e) => e.chapter.url == '/c-2');

      c.remove([first]);
      c.remove([second]);
      await Future<void>.delayed(Duration.zero);

      // Undo now applies to the second batch only; the first is already gone.
      expect(c.undo(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(c.visible.map((e) => e.chapter.url), contains('/c-2'));
    },
  );

  test('clearing history keeps read state', () async {
    // The user asked to forget a timeline, not to be told to re-read their
    // library.
    await seed(
      url: '/m',
      title: 'Example',
      chapters: ['/c-1', '/c-2'],
      read: ['/c-1'],
      favourite: true,
    );
    final c = await build();
    expect(c.visible, hasLength(1));

    await c.clearAll();

    expect(c.visible, isEmpty);
    final stored = await library.find(_sourceId, '/m');
    expect(
      stored!.chapters.firstWhere((x) => x.url == '/c-1').read,
      isTrue,
      reason: 'read state is not part of the timeline',
    );
    expect(stored.favorite, isTrue, reason: 'the library is untouched');
  });

  test('search matches the manga title, case-insensitively', () async {
    await seed(
      url: '/m',
      title: 'Raven Scans Weekly',
      chapters: ['/c-1'],
      read: ['/c-1'],
    );
    await seed(
      url: '/n',
      title: 'Something else',
      chapters: ['/c-1'],
      read: ['/c-1'],
    );
    final c = await build();

    c.setQuery('  RAVEN ');

    expect(c.visible.map((e) => e.entry.displayTitle), ['Raven Scans Weekly']);
  });
}
