import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

/// Reads and writes library entries.
///
/// An entry is identified by `(sourceId, url)` — the same pair everywhere, so
/// there is exactly one way to find a manga again.
abstract interface class LibraryRepository {
  /// The source id a library row points at, or null if it cannot be read.
  ///
  /// `MangaEntry.sourceId` is the decimal of the source's id, never a hash, so
  /// this is a straight conversion back. Kept here rather than on the
  /// implementation because it is the identity rule every caller has to share —
  /// the Kotlin app's highest-impact bug ever was screens disagreeing about it.
  static int? sourceIdOf(MangaEntry entry) => int.tryParse(entry.sourceId);

  /// The stored entry for this source and url, or null.
  Future<MangaEntry?> find(int sourceId, String url);

  /// Stores or refreshes what a source reported, and returns the row.
  ///
  /// Creates the entry if it is new. Never sets [MangaEntry.favorite]: saving
  /// what a source said is not the same as the user adding it to their library,
  /// and conflating the two silently fills the library with everything opened.
  Future<MangaEntry> upsertFromSource({
    required int sourceId,
    required String url,
    required MManga manga,
  });

  /// Toggles library membership, returning the new state.
  Future<bool> toggleFavorite(int sourceId, String url);

  Future<List<MangaEntry>> favorites();

  /// Every stored entry, favourite or not.
  ///
  /// History spans more than the library: a chapter read from a source and
  /// never added is exactly the thing a user comes back looking for, and
  /// filtering to favourites would lose it.
  Future<List<MangaEntry>> allEntries();

  /// Forgets that one chapter was read, leaving the entry and the rest alone.
  Future<void> clearChapterHistory(int sourceId, String url, String chapterUrl);

  /// Forgets every read timestamp. Read state itself is untouched: the user
  /// asked to clear a *timeline*, not to be told to re-read their library.
  Future<void> clearHistory();

  /// Marks a chapter read or unread, by its url.
  Future<void> setChapterRead(
    int sourceId,
    String url,
    String chapterUrl,
    bool read,
  );

  /// Records reading position for one chapter.
  ///
  /// [markRead] only ever sets read to true. The reader calls this on every
  /// page change, and a chapter the user finished earlier must not flip back to
  /// unread because they reopened it and looked at page one.
  Future<void> updateChapterProgress({
    required int sourceId,
    required String url,
    required String chapterUrl,
    required int lastPageRead,
    required int totalPages,
    double? currentOffset,
    double? maxOffset,
    bool markRead = false,
  });
}
