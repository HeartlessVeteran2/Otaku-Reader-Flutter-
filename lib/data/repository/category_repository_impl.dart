import 'dart:async';

import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  final _changes = StreamController<void>.broadcast();

  Future<void> _lock = Future.value();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Serialises every mutation, because each one reads the table and then
  /// writes a value derived from what it read.
  ///
  /// The precondition this repo's own rule states is met here and was
  /// **measured** rather than assumed, because the inverse mistake — a lock
  /// added by analogy where the reads were synchronous — is also in the
  /// mistakes table. Isar's `findAll` and `writeTxn` are genuinely async, so
  /// there is a yield point between the read and the write. Two `create` calls
  /// fired together produced `[A=0, B=0]`; a `delete` racing a `create`
  /// produced `[B=0, C=1, D=3]` — a gap at 2, which the *next* create walks
  /// straight into. Neither is a lost update the caller can see: the damage is
  /// two categories sharing one position, sorted against each other by nothing.
  ///
  /// Not reentrant, so the private helpers below deliberately do not take it.
  Future<T> _withLock<T>(Future<T> Function() body) {
    final result = _lock.then((_) => body());
    // The chain must survive a failed body, or one error wedges every later
    // caller on a future that never completes.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<List<CategoryEntry>> all() => _all();

  /// Unlocked, so the locked bodies can call it without deadlocking. A read on
  /// its own needs no lock: it is one Isar call, not a read-modify-write.
  Future<List<CategoryEntry>> _all() async {
    final rows = await db.isar.categoryEntrys.where().findAll();
    // Sorted here rather than by an Isar index, because `order` is rewritten
    // wholesale by `reorder` and an index would be maintained on every one of
    // those writes for a list that is never more than a few dozen rows.
    rows.sort((a, b) => a.order.compareTo(b.order));
    return rows;
  }

  @override
  Future<CategoryEntry?> create(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value(null);

    return _withLock(() async {
      final existing = await _all();
      final row = CategoryEntry()
        ..name = trimmed
        // Safe **only because `order` is contiguous**, which `_assignOrder`
        // is what guarantees. The first draft used `length` with a comment
        // claiming it survived a gap; it does not. Delete a middle category and
        // the orders are `0, 2` with length 2, so the next `create` lands on 2
        // and collides — two rows at one position, sorted against each other by
        // nothing.
        ..order = existing.length;

      await db.isar.writeTxn(() => db.isar.categoryEntrys.put(row));
      _notify();
      return row;
    });
  }

  @override
  Future<bool> rename(int id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value(false);

    return _withLock(() async {
      final row = await db.isar.categoryEntrys.get(id);
      if (row == null) return false;

      row.name = trimmed;
      await db.isar.writeTxn(() => db.isar.categoryEntrys.put(row));
      _notify();
      return true;
    });
  }

  @override
  Future<void> delete(int id) => _withLock(() async {
    // One transaction over all three writes. A category removed while its ids
    // survive on library rows leaves those entries filtered out of every tab —
    // still favourite, still in the database, and unreachable from the grid.
    // The renumber is in here for the same reason rather than after it: a
    // failure between the two would leave the delete standing with a gap in
    // the order, and `create` counts rows to pick its next position.
    await db.isar.writeTxn(() async {
      await db.isar.categoryEntrys.delete(id);

      // Only the rows that actually name it. Rewriting every row would touch
      // the whole library to change a handful, and `dateAdded`/`lastRead` are
      // on the same object — a needless put is a needless chance to clobber.
      final affected = await db.isar.mangaEntrys
          .filter()
          .categoryIdsElementEqualTo(id)
          .findAll();
      for (final entry in affected) {
        entry.categoryIds = [
          for (final c in entry.categoryIds)
            if (c != id) c,
        ];
      }
      if (affected.isNotEmpty) await db.isar.mangaEntrys.putAll(affected);

      await _renumberIn(await _all());
    });
    _notify();
  });

  @override
  Future<void> reorder(List<int> ids) => _withLock(() async {
    final rows = await _all();
    final byId = {for (final r in rows) r.id: r};

    // The listed ids first, in the order given; then everything the caller
    // omitted, keeping its relative order. Two rules in one sequence: a stale
    // id is skipped rather than failing the drag, and an omitted id keeps its
    // row rather than being deleted by an oversight.
    final sequence = <CategoryEntry>[
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    final placed = {for (final r in sequence) r.id};
    sequence.addAll(rows.where((r) => !placed.contains(r.id)));

    final moved = _assignOrder(sequence);
    if (moved.isEmpty) return;
    await db.isar.writeTxn(() => db.isar.categoryEntrys.putAll(moved));
    _notify();
  });

  /// Writes `0 … n-1` over [sequence] inside an open transaction.
  Future<void> _renumberIn(List<CategoryEntry> sequence) async {
    final moved = _assignOrder(sequence);
    if (moved.isNotEmpty) await db.isar.categoryEntrys.putAll(moved);
  }

  /// Stamps `0 … n-1` onto [sequence] and returns only the rows that moved.
  ///
  /// Contiguity is an **invariant**, not a tidiness preference: [create] takes
  /// the next position from the row count, so a gap anywhere makes the next
  /// category collide with an existing one. Enforcing it in one place is what
  /// lets that stay a one-liner.
  ///
  /// Returning only what moved is what keeps a reorder that ends where it
  /// started — a drag the user cancelled — from writing and repainting.
  List<CategoryEntry> _assignOrder(List<CategoryEntry> sequence) {
    final moved = <CategoryEntry>[];
    for (var i = 0; i < sequence.length; i++) {
      if (sequence[i].order != i) {
        sequence[i].order = i;
        moved.add(sequence[i]);
      }
    }
    return moved;
  }

  @override
  Future<List<int>> categoriesOf(int sourceId, String url) async {
    final row = await _entry(sourceId, url);
    return row?.categoryIds ?? const [];
  }

  @override
  Future<void> setCategoriesFor(int sourceId, String url, List<int> ids) =>
      _withLock(() async {
        final row = await _entry(sourceId, url);
        if (row == null) return;

        // Filtered against what exists, not trusted from the caller. The picker
        // is built off a snapshot, so a category deleted between opening it and
        // saving would otherwise be written straight back onto the row — which
        // is the same dangling reference `delete` exists to prevent, arriving
        // from the other direction. The lock is what makes that check mean
        // anything: read the live set, then write, with no delete in between.
        final known = {for (final c in await _all()) c.id};
        final cleaned = <int>[];
        for (final id in ids) {
          if (known.contains(id) && !cleaned.contains(id)) cleaned.add(id);
        }

        row.categoryIds = cleaned;
        await db.isar.writeTxn(() => db.isar.mangaEntrys.put(row));
        _notify();
      });

  Future<MangaEntry?> _entry(int sourceId, String url) => db.isar.mangaEntrys
      .filter()
      .sourceIdEqualTo(sourceId.toString())
      .urlEqualTo(url)
      .findFirst();

  /// Closes the change stream. Teardown only.
  void dispose() => _changes.close();
}
