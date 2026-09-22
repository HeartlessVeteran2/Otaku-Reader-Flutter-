import 'package:otaku_reader/data/isar/category_entry.dart';

/// The library's categories, and which entries are in them.
///
/// **Both halves of this already shipped and nothing read either.**
/// `CategoryEntry` is in `AppDatabaseSchemas.all` and round-tripped by
/// `database_schema_test.dart`; `MangaEntry.categoryIds` is declared on every
/// row. A collection with no reader is the same state `FEATURES.md` exists to
/// catch, one layer below the dead reader keys.
///
/// **Every method here is synchronous, and that is load-bearing rather than a
/// convenience.** It is also this app's existing idiom — `LibraryRepository`,
/// `SourceRepository`, `ExtensionRepository` and `KvHelper` are `putSync` /
/// `findFirstSync` / `writeTxnSync` throughout, and a second, async idiom in
/// one repository would be a shape nobody else here has.
///
/// Two things follow from it, and the second is the point:
///
/// - **Read-modify-write is atomic by construction.** `create` picks its
///   position from the row count and `delete` renumbers what is left, so both
///   read before they write. With an `await` in between, two callers can
///   interleave: measured against an async draft of this file, two `create`
///   calls fired together produced two categories at position 0, and a
///   `delete` racing a `create` left a gap for the *next* create to collide
///   with. Synchronously there is no yield point between the read and the
///   write, so nothing can interleave on Dart's one thread — which is
///   `CLAUDE.md`'s rule about `_withRepoLock`, read the other way round. The
///   async draft grew a lock; this does not need one, and a lock here would
///   guard nothing while reading as though concurrency had been handled.
/// - **A `Future` return type would invite an `await` back in**, at which
///   point the atomicity disappears with no signature to notice it going.
///   That is exactly how a lock got added to the repo-health writes by
///   analogy and guarded nothing, and it is in the mistakes table.
abstract interface class CategoryRepository {
  /// Fires after any write, so a grid filtered by category repaints.
  ///
  /// Separate from `LibraryRepository.changes` on purpose: renaming a category
  /// changes no library row, and a library write changes no category. A screen
  /// listening to the wrong one rebuilds for events it does not care about and
  /// misses the one it does.
  Stream<void> get changes;

  /// Every category, in `order`.
  List<CategoryEntry> all();

  /// Creates a category at the end of the order and returns it.
  ///
  /// A blank or whitespace-only name is refused, because a nameless tab is a
  /// tab nobody can tell from its neighbour. Duplicates are **allowed**: two
  /// categories called "Reading" are a mess the user can see and fix, where a
  /// silent refusal looks like the button is broken. It also means the *name*
  /// is not a safe key — AnymeX's assignment dialog keys its before/after map
  /// by one, so two same-named lists share an entry and toggling either writes
  /// the other.
  CategoryEntry? create(String name);

  /// Renames a category. Returns false for a blank name or a missing id.
  bool rename(int id, String name);

  /// Deletes a category **and scrubs its id from every library row.**
  ///
  /// The sweep is the whole reason this is a repository method rather than a
  /// one-line delete. A row left pointing at a category that no longer exists
  /// is invisible to a grid that filters by membership — the manga is still in
  /// the library, still favourite, and simply cannot be found. That is the
  /// one-way-mapping failure the Kotlin app calls its highest-impact bug ever,
  /// reachable here through an ordinary delete.
  ///
  /// All of it happens in **one transaction**, so a failure cannot leave the
  /// category gone and the references behind, nor leave a gap in the order.
  void delete(int id);

  /// Rewrites the order to match [ids], first to last.
  ///
  /// Ids not in the list are left alone rather than dropped: a reorder that
  /// silently deletes a category the caller forgot to include is a data loss
  /// wearing a drag gesture.
  void reorder(List<int> ids);

  /// The categories a library row belongs to.
  List<int> categoriesOf(int sourceId, String url);

  /// Replaces a row's category membership.
  ///
  /// Ids that name no existing category are dropped, because the caller's list
  /// comes from a picker built off a snapshot — a category deleted on another
  /// screen between the open and the save would otherwise be written back.
  void setCategoriesFor(int sourceId, String url, List<int> ids);
}
