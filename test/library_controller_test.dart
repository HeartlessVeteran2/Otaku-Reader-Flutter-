import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

import 'helpers/isar_test_env.dart';

const _sourceId = 5;

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('libctl', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  Future<void> add(
    String url,
    String title, {
    int chapters = 0,
    int read = 0,
    bool favorite = true,
  }) async {
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: url,
      manga: MManga(
        name: title,
        chapters: [
          for (var i = 1; i <= chapters; i++)
            MChapter(url: '$url/c-$i', name: 'Chapter $i'),
        ],
      ),
    );
    for (var i = 1; i <= read; i++) {
      await library.setChapterRead(_sourceId, url, '$url/c-$i', true);
    }
    if (favorite) await library.toggleFavorite(_sourceId, url);
  }

  Future<LibraryController> build() async {
    final c = LibraryController(library: library)..onInit();
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('only favourites are listed', () async {
    await add('/a', 'Kept');
    await add('/b', 'Just opened', favorite: false);

    final c = await build();

    expect(c.visible.map((e) => e.title), ['Kept']);
  });

  test('sorts by title and flips on a second tap of the same option', () async {
    await add('/a', 'Berserk');
    await add('/b', 'Akira');

    final c = await build();
    expect(c.visible.map((e) => e.title), ['Akira', 'Berserk']);

    c.setSort(LibrarySort.title);
    expect(c.visible.map((e) => e.title), ['Berserk', 'Akira']);
  });

  test('choosing a different option does not flip the direction', () async {
    await add('/a', 'A', chapters: 2);
    await add('/b', 'B', chapters: 5);

    final c = await build();
    c.setSort(LibrarySort.unread);

    expect(c.ascending.value, isTrue);
    expect(c.visible.map((e) => e.title), ['A', 'B']);
  });

  test('an entry never read sorts last, whichever way the list runs', () async {
    // Null has no position on a "last read" axis. Letting it win the top buries
    // what the user actually wants to get back to.
    await add('/a', 'Read', chapters: 1, read: 1);
    await add('/b', 'Never opened', chapters: 1);

    final c = await build();
    c.setSort(LibrarySort.lastRead);
    expect(c.visible.last.title, 'Never opened');

    c.setSort(LibrarySort.lastRead); // flip
    expect(c.visible.last.title, 'Never opened');
  });

  test('unread counts only unread chapters', () async {
    await add('/a', 'Partly read', chapters: 5, read: 2);

    final c = await build();

    expect(LibraryController.unreadOf(c.visible.single), 3);
  });

  test('search is case-insensitive and matches a substring', () async {
    await add('/a', 'Vinland Saga');
    await add('/b', 'Berserk');

    final c = await build();
    c.setQuery('  LAND ');

    expect(c.visible.map((e) => e.title), ['Vinland Saga']);
  });

  test('the source key on a library row converts back to the source', () async {
    await add('/a', 'Kept');

    final c = await build();

    expect(
      LibraryRepositoryImpl.sourceIdFrom(c.visible.single.sourceId),
      _sourceId,
    );
  });
}
