import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/data/repository/category_repository_impl.dart';
import 'package:isar_community/isar.dart';

import 'helpers/isar_test_env.dart';

/// The library's categories.
///
/// The assertion that carries this file is the **deletion sweep**: removing a
/// category has to scrub its id off every library row, or those entries are
/// filtered out of every tab while still sitting in the database, favourite
/// and unreachable. That is the one-way-mapping failure the Kotlin app calls
/// its highest-impact bug ever, reachable here through an ordinary delete.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('categories', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  late CategoryRepositoryImpl repo;

  setUp(() {
    env!.clear();
    repo = CategoryRepositoryImpl();
  });

  tearDown(() => repo.dispose());

  Future<MangaEntry> addManga(
    String url, {
    List<int> categories = const [],
  }) async {
    final row = MangaEntry()
      ..sourceId = '11'
      ..url = url
      ..title = url
      ..favorite = true
      ..categoryIds = categories;
    await db.isar.writeTxn(() => db.isar.mangaEntrys.put(row));
    return row;
  }

  Future<List<int>> categoriesFor(String url) async =>
      (await db.isar.mangaEntrys
              .filter()
              .sourceIdEqualTo('11')
              .urlEqualTo(url)
              .findFirst())
          ?.categoryIds ??
      const [];

  group('creating', () {
    test('appends to the order', () async {
      final a = repo.create('Reading');
      final b = repo.create('On hold');
      expect(a!.order, 0);
      expect(b!.order, 1);
      expect(repo.all().map((c) => c.name), ['Reading', 'On hold']);
    });

    test('refuses a blank name', () async {
      expect(repo.create(''), isNull);
      expect(repo.create('   '), isNull);
      expect(repo.all(), isEmpty);
    });

    test('trims, and allows a duplicate name', () async {
      repo.create('  Reading  ');
      repo.create('Reading');
      // Two categories with one name is a mess the user can see and fix. A
      // silent refusal reads as the button being broken.
      expect(repo.all().map((c) => c.name), ['Reading', 'Reading']);
    });

    test('numbers from the count, so a gap does not collide', () async {
      final a = repo.create('A');
      repo.create('B');
      repo.delete(a!.id);
      final c = repo.create('C');
      // `last.order + 1` would be 2 here and collide with B. The count is 1.
      expect(c!.order, 1);
      expect(repo.all().map((c) => c.name), ['B', 'C']);
    });
  });

  group('deleting', () {
    test('scrubs the id from every library row that names it', () async {
      final keep = repo.create('Keep');
      final drop = repo.create('Drop');

      await addManga('/a', categories: [keep!.id, drop!.id]);
      await addManga('/b', categories: [drop.id]);
      await addManga('/c', categories: [keep.id]);

      repo.delete(drop.id);

      // The whole point. A row still naming a deleted category is invisible to
      // a grid that filters by membership.
      expect(await categoriesFor('/a'), [keep.id]);
      expect(await categoriesFor('/b'), isEmpty);
      expect(await categoriesFor('/c'), [keep.id]);
    });

    test('leaves rows that never named it untouched', () async {
      final keep = repo.create('Keep');
      final drop = repo.create('Drop');
      await addManga('/untouched', categories: [keep!.id]);

      repo.delete(drop!.id);

      expect(await categoriesFor('/untouched'), [keep.id]);
    });

    test('removes the category itself', () async {
      final row = repo.create('Gone');
      repo.delete(row!.id);
      expect(repo.all(), isEmpty);
    });
  });

  group('reordering', () {
    test('rewrites order to match the list', () async {
      final a = repo.create('A');
      final b = repo.create('B');
      final c = repo.create('C');

      repo.reorder([c!.id, a!.id, b!.id]);

      expect(repo.all().map((r) => r.name), ['C', 'A', 'B']);
    });

    test('skips an id that no longer exists rather than failing', () async {
      final a = repo.create('A');
      final b = repo.create('B');
      repo.delete(a!.id);

      // The list came from a drag on a snapshot. A stale id must not strand
      // the surviving rows at their old positions.
      repo.reorder([a.id, b!.id]);

      expect(repo.all().map((r) => r.name), ['B']);
      expect(repo.all().first.order, 0);
    });

    test('leaves an id the caller omitted alone', () async {
      final a = repo.create('A');
      final b = repo.create('B');
      repo.create('C');

      repo.reorder([b!.id, a!.id]);

      // C keeps its row. A reorder that silently deletes what the caller
      // forgot to list is data loss wearing a drag gesture.
      expect(repo.all().map((r) => r.name), contains('C'));
      expect(repo.all(), hasLength(3));
    });
  });

  group('membership', () {
    test('round-trips through the manga row', () async {
      final a = repo.create('A');
      final b = repo.create('B');
      await addManga('/x');

      repo.setCategoriesFor(11, '/x', [a!.id, b!.id]);

      expect(repo.categoriesOf(11, '/x'), [a.id, b.id]);
    });

    test('drops an id naming no existing category', () async {
      final a = repo.create('A');
      final gone = repo.create('Gone');
      await addManga('/x');
      repo.delete(gone!.id);

      // The picker is built off a snapshot; a category deleted between opening
      // it and saving would otherwise be written straight back onto the row --
      // the same dangling reference `delete` exists to prevent, arriving from
      // the other direction.
      repo.setCategoriesFor(11, '/x', [a!.id, gone.id]);

      expect(repo.categoriesOf(11, '/x'), [a.id]);
    });

    test('drops a repeated id', () async {
      final a = repo.create('A');
      await addManga('/x');
      repo.setCategoriesFor(11, '/x', [a!.id, a.id]);
      expect(repo.categoriesOf(11, '/x'), [a.id]);
    });

    test('a row that is not in the library is a no-op, not a throw', () async {
      final a = repo.create('A');
      repo.setCategoriesFor(11, '/missing', [a!.id]);
      expect(repo.categoriesOf(11, '/missing'), isEmpty);
    });
  });

  group('order stays contiguous, which create depends on', () {
    // The invariant nothing was checking. `create` takes the next position
    // from the row *count*, so any gap makes the next category collide with an
    // existing one -- two rows at one position, ordered against each other by
    // nothing. A first draft left gaps after both a delete and a skipped
    // reorder while its own comment claimed otherwise.
    Future<void> expectContiguous() async {
      final orders = repo.all().map((c) => c.order).toList();
      expect(
        orders,
        List.generate(orders.length, (i) => i),
        reason: 'orders should be 0..n-1',
      );
    }

    test('after deleting from the middle', () async {
      repo.create('A');
      final b = repo.create('B');
      repo.create('C');
      repo.delete(b!.id);
      await expectContiguous();

      // The collision the gap would have caused.
      final d = repo.create('D');
      expect(repo.all().where((c) => c.order == d!.order), hasLength(1));
    });

    test('after a reorder that skipped a stale id', () async {
      final a = repo.create('A');
      final b = repo.create('B');
      repo.delete(a!.id);
      repo.reorder([a.id, b!.id]);
      await expectContiguous();
    });

    test('after a reorder that omitted an id', () async {
      final a = repo.create('A');
      final b = repo.create('B');
      repo.create('C');
      repo.reorder([b!.id, a!.id]);
      await expectContiguous();
    });
  });

  group('atomicity is structural, not locked', () {
    // Every mutation reads the table and then writes a value derived from what
    // it read -- `create` takes its position from the row count, `delete`
    // renumbers what is left. An async draft of this repository had a genuine
    // yield point between those two halves, and it raced: measured, two
    // `create` calls fired together produced `[A=0, B=0]`, and a `delete`
    // racing a `create` produced `[B=0, C=1, D=3]`, leaving a gap at 2 for the
    // *next* create to collide with.
    //
    // It is synchronous now, matching every other repository in this app, so
    // there is no yield point for a second caller to land in. **That is why
    // there is no lock**, and it is the precondition `CLAUDE.md` states: a
    // lock is for an `await` between the read and the write, and one added
    // without that guards nothing while reading as though concurrency had been
    // handled.
    //
    // The guard for that is the **type system**, not a runtime assertion. The
    // two cases above cannot even be written any more: `Future.wait([...])`
    // does not accept a `CategoryEntry?`. Making any of these methods return a
    // `Future` again breaks this file at compile time, which is a harder
    // failure than a test.

    test('a full read-modify-write cycle needs no await', () {
      // Deliberately a synchronous test body -- no `async`, so the analyzer
      // rejects an `await` here and the compiler rejects a `Future` return.
      // Every call below is one turn of the event loop, start to finish.
      final a = repo.create('A');
      repo.create('B');
      repo.create('C');
      repo.delete(a!.id);
      final d = repo.create('D');

      // The positions that the async version got wrong: the delete closed its
      // gap before the create read the count, because nothing could run in
      // between.
      final orders = repo.all().map((r) => r.order).toList()..sort();
      expect(orders, [0, 1, 2]);
      expect(d, isNotNull);
      expect(repo.all().map((r) => r.name), ['B', 'C', 'D']);
    });
  });

  test('every write announces itself', () async {
    // A grid filtered by category has to repaint when a category is renamed,
    // and `LibraryRepository.changes` never fires for that -- renaming touches
    // no library row.
    final seen = <void>[];
    final sub = repo.changes.listen(seen.add);
    addTearDown(sub.cancel);

    final row = repo.create('A');
    repo.rename(row!.id, 'B');
    repo.reorder([row.id]);
    repo.delete(row.id);
    await Future<void>.delayed(Duration.zero);

    // Three writes: create, rename, delete. The reorder is a no-op at one item
    // already in position, and deliberately stays silent rather than
    // announcing a change it did not make.
    expect(seen, hasLength(3));
  });
}
