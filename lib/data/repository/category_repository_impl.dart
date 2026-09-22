import 'dart:async';

import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';

/// Synchronous throughout — see [CategoryRepository] for why that is the
/// invariant rather than a style choice, and this app's other repositories for
/// the precedent.
class CategoryRepositoryImpl implements CategoryRepository {
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  List<CategoryEntry> all() {
    final rows = db.isar.categoryEntrys.where().findAllSync();
    // Sorted here rather than by an Isar index, because `order` is rewritten
    // wholesale by `reorder` and an index would be maintained on every one of
    // those writes for a list that is never more than a few dozen rows.
    rows.sort((a, b) => a.order.compareTo(b.order));
    return rows;
  }

  @override
  CategoryEntry? create(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final row = CategoryEntry()
      ..name = trimmed
      // Safe **only because `order` is contiguous**, which `_assignOrder` is
      // what guarantees. An earlier draft used the row count with a comment
      // claiming it survived a gap; it does not. Delete the middle of three
      // and the orders are `0, 2` with a count of 2, so the next create lands
      // on 2 and collides — two rows at one position, sorted against each
      // other by nothing.
      ..order = all().length;

    db.isar.writeTxnSync(() => db.isar.categoryEntrys.putSync(row));
    _notify();
    return row;
  }

  @override
  bool rename(int id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    final row = db.isar.categoryEntrys.getSync(id);
    if (row == null) return false;

    row.name = trimmed;
    db.isar.writeTxnSync(() => db.isar.categoryEntrys.putSync(row));
    _notify();
    return true;
  }

  @override
  void delete(int id) {
    // One transaction over all three writes. A category removed while its ids
    // survive on library rows leaves those entries filtered out of every tab —
    // still favourite, still in the database, and unreachable from the grid.
    // The renumber is in here rather than after it for the same reason: a
    // failure between the two would leave the delete standing with a gap in
    // the order, which `create` then collides with.
    db.isar.writeTxnSync(() {
      db.isar.categoryEntrys.deleteSync(id);

      // Only the rows that actually name it. Rewriting every row would touch
      // the whole library to change a handful, and `dateAdded`/`lastRead` are
      // on the same object — a needless put is a needless chance to clobber.
      final affected = db.isar.mangaEntrys
          .filter()
          .categoryIdsElementEqualTo(id)
          .findAllSync();
      for (final entry in affected) {
        entry.categoryIds = [
          for (final c in entry.categoryIds)
            if (c != id) c,
        ];
      }
      if (affected.isNotEmpty) db.isar.mangaEntrys.putAllSync(affected);

      final moved = _assignOrder(all());
      if (moved.isNotEmpty) db.isar.categoryEntrys.putAllSync(moved);
    });
    _notify();
  }

  @override
  void reorder(List<int> ids) {
    final rows = all();
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
    // Silent when nothing moved — a drag the user cancelled must not repaint
    // every listener.
    if (moved.isEmpty) return;
    db.isar.writeTxnSync(() => db.isar.categoryEntrys.putAllSync(moved));
    _notify();
  }

  /// Stamps `0 … n-1` onto [sequence] and returns only the rows that moved.
  ///
  /// Contiguity is an **invariant**, not a tidiness preference: [create] takes
  /// the next position from the row count, so a gap anywhere makes the next
  /// category collide with an existing one. Enforcing it in one place is what
  /// lets that stay a one-liner.
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
  List<int> categoriesOf(int sourceId, String url) =>
      _entry(sourceId, url)?.categoryIds ?? const [];

  @override
  void setCategoriesFor(int sourceId, String url, List<int> ids) {
    final row = _entry(sourceId, url);
    if (row == null) return;

    // Filtered against what exists, not trusted from the caller. The picker is
    // built off a snapshot, so a category deleted between opening it and
    // saving would otherwise be written straight back onto the row — which is
    // the same dangling reference `delete` exists to prevent, arriving from
    // the other direction. Reading the live set and writing in one turn is
    // what makes that check mean anything.
    final known = {for (final c in all()) c.id};
    final cleaned = <int>[];
    for (final id in ids) {
      if (known.contains(id) && !cleaned.contains(id)) cleaned.add(id);
    }

    row.categoryIds = cleaned;
    db.isar.writeTxnSync(() => db.isar.mangaEntrys.putSync(row));
    _notify();
  }

  MangaEntry? _entry(int sourceId, String url) => db.isar.mangaEntrys
      .filter()
      .sourceIdEqualTo(sourceId.toString())
      .urlEqualTo(url)
      .findFirstSync();

  /// Closes the change stream. Teardown only.
  void dispose() => _changes.close();
}
