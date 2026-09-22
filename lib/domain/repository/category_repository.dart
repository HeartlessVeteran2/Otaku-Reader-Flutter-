import 'package:otaku_reader/data/isar/category_entry.dart';

/// The library's categories, and which entries are in them.
///
/// **Both halves of this already shipped and nothing read either.**
/// `CategoryEntry` is in `AppDatabaseSchemas.all` and round-tripped by
/// `database_schema_test.dart`; `MangaEntry.categoryIds` is declared on every
/// row. A collection with no reader is the same state `FEATURES.md` exists to
/// catch, one layer below the dead keys the display group just closed.
abstract interface class CategoryRepository {
  /// Fires after any write, so a grid filtered by category repaints.
  ///
  /// Separate from `LibraryRepository.changes` on purpose: renaming a category
  /// changes no library row, and a library write changes no category. A screen
  /// listening to the wrong one rebuilds for events it does not care about and
  /// misses the one it does.
  Stream<void> get changes;

  /// Every category, in `order`.
  Future<List<CategoryEntry>> all();

  /// Creates a category at the end of the order and returns it.
  ///
  /// A blank or whitespace-only name is refused, because a nameless tab is a
  /// tab nobody can tell from its neighbour. Duplicates are **allowed**: two
  /// categories called "Reading" are a mess the user can see and fix, where a
  /// silent refusal looks like the button is broken.
  Future<CategoryEntry?> create(String name);

  /// Renames a category. Returns false for a blank name or a missing id.
  Future<bool> rename(int id, String name);

  /// Deletes a category **and scrubs its id from every library row.**
  ///
  /// The sweep is the whole reason this is a repository method rather than a
  /// one-line delete. A row left pointing at a category that no longer exists
  /// is invisible to a grid that filters by membership — the manga is still in
  /// the library, still favourite, and simply cannot be found. That is the
  /// one-way-mapping failure the Kotlin app calls its highest-impact bug ever,
  /// reachable here through an ordinary delete.
  ///
  /// Both writes happen in **one transaction**, so a failure cannot leave the
  /// category gone and the references behind.
  Future<void> delete(int id);

  /// Rewrites the order to match [ids], first to last.
  ///
  /// Ids not in the list are left alone rather than dropped: a reorder that
  /// silently deletes a category the caller forgot to include is a data loss
  /// wearing a drag gesture.
  Future<void> reorder(List<int> ids);

  /// The categories a library row belongs to.
  Future<List<int>> categoriesOf(int sourceId, String url);

  /// Replaces a row's category membership.
  ///
  /// Ids that name no existing category are dropped, because the caller's list
  /// comes from a picker built off a snapshot — a category deleted on another
  /// screen between the open and the save would otherwise be written back.
  Future<void> setCategoriesFor(int sourceId, String url, List<int> ids);
}
