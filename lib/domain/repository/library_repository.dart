import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

/// Reads and writes library entries.
///
/// An entry is identified by `(sourceId, url)` — the same pair everywhere, so
/// there is exactly one way to find a manga again.
abstract interface class LibraryRepository {
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
    bool markRead = false,
  });
}
