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
      final a = await repo.create('Reading');
      final b = await repo.create('On hold');
      expect(a!.order, 0);
      expect(b!.order, 1);
      expect((await repo.all()).map((c) => c.name), ['Reading', 'On hold']);
    });

    test('refuses a blank name', () async {
      expect(await repo.create(''), isNull);
      expect(await repo.create('   '), isNull);
      expect(await repo.all(), isEmpty);
    });

    test('trims, and allows a duplicate name', () async {
      await repo.create('  Reading  ');
      await repo.create('Reading');
      // Two categories with one name is a mess the user can see and fix. A
      // silent refusal reads as the button being broken.
      expect((await repo.all()).map((c) => c.name), ['Reading', 'Reading']);
    });

    test('numbers from the count, so a gap does not collide', () async {
      final a = await repo.create('A');
      await repo.create('B');
      await repo.delete(a!.id);
      final c = await repo.create('C');
      // `last.order + 1` would be 2 here and collide with B. The count is 1.
      expect(c!.order, 1);
      expect((await repo.all()).map((c) => c.name), ['B', 'C']);
    });
  });

  group('deleting', () {
    test('scrubs the id from every library row that names it', () async {
      final keep = await repo.create('Keep');
      final drop = await repo.create('Drop');

      await addManga('/a', categories: [keep!.id, drop!.id]);
      await addManga('/b', categories: [drop.id]);
      await addManga('/c', categories: [keep.id]);

      await repo.delete(drop.id);

      // The whole point. A row still naming a deleted category is invisible to
      // a grid that filters by membership.
      expect(await categoriesFor('/a'), [keep.id]);
      expect(await categoriesFor('/b'), isEmpty);
      expect(await categoriesFor('/c'), [keep.id]);
    });

    test('leaves rows that never named it untouched', () async {
      final keep = await repo.create('Keep');
      final drop = await repo.create('Drop');
      await addManga('/untouched', categories: [keep!.id]);

      await repo.delete(drop!.id);

      expect(await categoriesFor('/untouched'), [keep.id]);
    });

    test('removes the category itself', () async {
      final row = await repo.create('Gone');
      await repo.delete(row!.id);
      expect(await repo.all(), isEmpty);
    });
  });

  group('reordering', () {
    test('rewrites order to match the list', () async {
      final a = await repo.create('A');
      final b = await repo.create('B');
      final c = await repo.create('C');

      await repo.reorder([c!.id, a!.id, b!.id]);

      expect((await repo.all()).map((r) => r.name), ['C', 'A', 'B']);
    });

    test('skips an id that no longer exists rather than failing', () async {
      final a = await repo.create('A');
      final b = await repo.create('B');
      await repo.delete(a!.id);

      // The list came from a drag on a snapshot. A stale id must not strand
      // the surviving rows at their old positions.
      await repo.reorder([a.id, b!.id]);

      expect((await repo.all()).map((r) => r.name), ['B']);
      expect((await repo.all()).first.order, 0);
    });

    test('leaves an id the caller omitted alone', () async {
      final a = await repo.create('A');
      final b = await repo.create('B');
      await repo.create('C');

      await repo.reorder([b!.id, a!.id]);

      // C keeps its row. A reorder that silently deletes what the caller
      // forgot to list is data loss wearing a drag gesture.
      expect((await repo.all()).map((r) => r.name), contains('C'));
      expect(await repo.all(), hasLength(3));
    });
  });

  group('membership', () {
    test('round-trips through the manga row', () async {
      final a = await repo.create('A');
      final b = await repo.create('B');
      await addManga('/x');

      await repo.setCategoriesFor(11, '/x', [a!.id, b!.id]);

      expect(await repo.categoriesOf(11, '/x'), [a.id, b.id]);
    });

    test('drops an id naming no existing category', () async {
      final a = await repo.create('A');
      final gone = await repo.create('Gone');
      await addManga('/x');
      await repo.delete(gone!.id);

      // The picker is built off a snapshot; a category deleted between opening
      // it and saving would otherwise be written straight back onto the row --
      // the same dangling reference `delete` exists to prevent, arriving from
      // the other direction.
      await repo.setCategoriesFor(11, '/x', [a!.id, gone.id]);

      expect(await repo.categoriesOf(11, '/x'), [a.id]);
    });

    test('drops a repeated id', () async {
      final a = await repo.create('A');
      await addManga('/x');
      await repo.setCategoriesFor(11, '/x', [a!.id, a.id]);
      expect(await repo.categoriesOf(11, '/x'), [a.id]);
    });

    test('a row that is not in the library is a no-op, not a throw', () async {
      final a = await repo.create('A');
      await repo.setCategoriesFor(11, '/missing', [a!.id]);
      expect(await repo.categoriesOf(11, '/missing'), isEmpty);
    });
  });

  group('order stays contiguous, which create depends on', () {
    // The invariant nothing was checking. `create` takes the next position
    // from the row *count*, so any gap makes the next category collide with an
    // existing one -- two rows at one position, ordered against each other by
    // nothing. A first draft left gaps after both a delete and a skipped
    // reorder while its own comment claimed otherwise.
    Future<void> expectContiguous() async {
      final orders = (await repo.all()).map((c) => c.order).toList();
      expect(
        orders,
        List.generate(orders.length, (i) => i),
        reason: 'orders should be 0..n-1',
      );
    }

    test('after deleting from the middle', () async {
      await repo.create('A');
      final b = await repo.create('B');
      await repo.create('C');
      await repo.delete(b!.id);
      await expectContiguous();

      // The collision the gap would have caused.
      final d = await repo.create('D');
      expect(
        (await repo.all()).where((c) => c.order == d!.order),
        hasLength(1),
      );
    });

    test('after a reorder that skipped a stale id', () async {
      final a = await repo.create('A');
      final b = await repo.create('B');
      await repo.delete(a!.id);
      await repo.reorder([a.id, b!.id]);
      await expectContiguous();
    });

    test('after a reorder that omitted an id', () async {
      final a = await repo.create('A');
      final b = await repo.create('B');
      await repo.create('C');
      await repo.reorder([b!.id, a!.id]);
      await expectContiguous();
    });
  });

  group('concurrent writes', () {
    // Every mutation reads the table and then writes a value derived from what
    // it read, with a genuine yield point in between -- so two callers can
    // interleave. These two cases were measured against the unlocked version
    // before the lock was written, because the inverse mistake (a lock added
    // by analogy where the reads were synchronous, guarding nothing) is also
    // in this project's mistakes table.
    //
    // They assert the *order column*, not the return values: both calls
    // succeed either way, and the damage is two categories sharing one
    // position with nothing to sort them against.

    test('two creates fired together take different positions', () async {
      // Unlocked this produced `[A=0, B=0]`.
      await Future.wait([repo.create('A'), repo.create('B')]);

      final orders = (await repo.all()).map((r) => r.order).toList()..sort();
      expect(orders, [0, 1]);
    });

    test('a create racing a delete does not land in the gap', () async {
      // Unlocked this produced `[B=0, C=1, D=3]` -- the delete renumbered
      // while the create was reading, so the new row took a position past the
      // end and left 2 empty for the *next* create to collide with.
      final a = await repo.create('A');
      await repo.create('B');
      await repo.create('C');

      await Future.wait([repo.delete(a!.id), repo.create('D')]);

      final orders = (await repo.all()).map((r) => r.order).toList()..sort();
      expect(orders, [0, 1, 2]);
    });
  });

  test('every write announces itself', () async {
    // A grid filtered by category has to repaint when a category is renamed,
    // and `LibraryRepository.changes` never fires for that -- renaming touches
    // no library row.
    final seen = <void>[];
    final sub = repo.changes.listen(seen.add);
    addTearDown(sub.cancel);

    final row = await repo.create('A');
    await repo.rename(row!.id, 'B');
    await repo.reorder([row.id]);
    await repo.delete(row.id);
    await Future<void>.delayed(Duration.zero);

    // Three writes: create, rename, delete. The reorder is a no-op at one item
    // already in position, and deliberately stays silent rather than
    // announcing a change it did not make.
    expect(seen, hasLength(3));
  });
}
