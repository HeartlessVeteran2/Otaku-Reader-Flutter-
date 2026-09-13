import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_status.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  /// A source's numeric id, as stored on a library row.
  ///
  /// Stored as the **decimal of the id itself**, never a hash. The Kotlin app
  /// keyed rows by `sourceStringId.hashCode()` and calls the resulting one-way
  /// mapping its highest-impact bug ever: every screen that needed to go from a
  /// library row back to its source failed for every entry. `int.parse` takes
  /// this one straight back.
  static String keyFor(int sourceId) => sourceId.toString();

  static int? sourceIdFrom(String key) => int.tryParse(key);

  @override
  Future<MangaEntry?> find(int sourceId, String url) async => db
      .isar
      .mangaEntrys
      .filter()
      .sourceIdEqualTo(keyFor(sourceId))
      .urlEqualTo(url)
      .findFirstSync();

  @override
  Future<MangaEntry> upsertFromSource({
    required int sourceId,
    required String url,
    required MManga manga,
  }) async {
    late MangaEntry saved;
    db.isar.writeTxnSync(() {
      // Read and write inside one transaction: this is a read-then-act
      // sequence, and opening a detail page twice in quick succession would
      // otherwise create two rows for the same manga.
      final existing = db.isar.mangaEntrys
          .filter()
          .sourceIdEqualTo(keyFor(sourceId))
          .urlEqualTo(url)
          .findFirstSync();

      // `title` is `late` and non-nullable, so a new row must carry one before
      // the merge below reads it -- otherwise the very first save of any manga
      // throws LateInitializationError. 'Untitled' is a placeholder that the
      // next refresh replaces as soon as the source reports a name.
      final entry =
          existing ??
          (MangaEntry()
            ..sourceId = keyFor(sourceId)
            ..url = url
            ..title = (manga.name?.trim().isNotEmpty ?? false)
                ? manga.name!
                : 'Untitled'
            ..dateAdded = DateTime.now());

      // Source-owned fields. A blank from the source is a gap, not an erasure:
      // details pages routinely omit an author the listing had, and letting the
      // blank win would wipe good data on every refresh.
      entry.title = _prefer(manga.name, entry.title);
      entry.thumbnailUrl = _preferNullable(manga.imageUrl, entry.thumbnailUrl);
      entry.author = _preferNullable(manga.author, entry.author);
      entry.artist = _preferNullable(manga.artist, entry.artist);
      entry.description = _preferNullable(manga.description, entry.description);
      if (manga.genre?.isNotEmpty ?? false) entry.genres = manga.genre!;
      if (manga.status != null && manga.status != Status.unknown) {
        entry.status = manga.status!.index;
      }
      entry.lastUpdate = DateTime.now();
      entry.chapters = _mergeChapters(
        entry.chapters,
        manga.chapters ?? const [],
      );

      db.isar.mangaEntrys.putSync(entry);
      saved = entry;
    });
    return saved;
  }

  /// Folds freshly fetched chapters into the stored ones.
  ///
  /// The split between what the **source** owns and what the **user** owns is
  /// the whole point. A refresh brings a corrected name or a scanlator; it must
  /// never bring `read = false`. Losing read state on a refresh is the kind of
  /// bug a user notices immediately and cannot undo.
  ///
  /// Keyed by chapter url, because that is the only field a source guarantees
  /// and the only one it will not renumber.
  static List<Chapter> _mergeChapters(
    List<Chapter> stored,
    List<MChapter> incoming,
  ) {
    final byUrl = {for (final c in stored) c.url: c};
    final merged = <Chapter>[];

    for (final fresh in incoming) {
      final existing = byUrl[fresh.url];
      final chapter = existing ?? Chapter();
      chapter
        ..url = fresh.url
        ..name = fresh.name ?? chapter.name
        ..scanlator = fresh.scanlator ?? chapter.scanlator
        ..dateUpload = fresh.dateUpload ?? chapter.dateUpload
        ..number = parseChapterNumber(fresh.name) ?? chapter.number;
      // read / lastPageRead / currentOffset / maxOffset / lastReadTime /
      // localPath are deliberately untouched: they belong to the user.
      merged.add(chapter);
    }

    // A chapter the source no longer lists but the user has read is kept. Sites
    // drop and re-add chapters constantly (DMCA, re-uploads, renumbering), and
    // dropping it would erase the fact that it was read.
    final freshUrls = incoming.map((c) => c.url).toSet();
    for (final old in stored) {
      if (freshUrls.contains(old.url)) continue;
      if (old.read || old.lastPageRead != null) merged.add(old);
    }

    return merged;
  }

  /// Pulls a chapter number out of a title.
  ///
  /// Fractional chapters are real (12.5) and common, so this returns a double.
  /// A title with no number at all is normal — many sources title one-shots and
  /// extras by name — and yields null rather than a misleading 0.
  static double? parseChapterNumber(String? name) {
    if (name == null) return null;
    // Skip a leading volume marker so "Vol.2 Ch.5" is chapter 5, not 2.
    final withoutVolume = name.replaceAll(
      RegExp(r'vol(ume)?\.?\s*\d+(\.\d+)?', caseSensitive: false),
      '',
    );
    final match = RegExp(
      r'(?:ch(?:apter)?\.?\s*)?(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(withoutVolume);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  @override
  Future<bool> toggleFavorite(int sourceId, String url) async {
    var result = false;
    db.isar.writeTxnSync(() {
      final entry = db.isar.mangaEntrys
          .filter()
          .sourceIdEqualTo(keyFor(sourceId))
          .urlEqualTo(url)
          .findFirstSync();
      if (entry == null) return;
      entry.favorite = !entry.favorite;
      if (entry.favorite) entry.dateAdded ??= DateTime.now();
      db.isar.mangaEntrys.putSync(entry);
      result = entry.favorite;
    });
    return result;
  }

  @override
  Future<List<MangaEntry>> favorites() async =>
      db.isar.mangaEntrys.filter().favoriteEqualTo(true).findAllSync();

  @override
  Future<void> setChapterRead(
    int sourceId,
    String url,
    String chapterUrl,
    bool read,
  ) async {
    db.isar.writeTxnSync(() {
      final entry = db.isar.mangaEntrys
          .filter()
          .sourceIdEqualTo(keyFor(sourceId))
          .urlEqualTo(url)
          .findFirstSync();
      if (entry == null) return;
      // Isar embedded lists are replaced wholesale, so the list is rebuilt
      // rather than mutated in place.
      entry.chapters = [
        for (final c in entry.chapters)
          if (c.url == chapterUrl)
            (c
              ..read = read
              ..lastReadTime = read
                  ? DateTime.now().millisecondsSinceEpoch
                  : c.lastReadTime)
          else
            c,
      ];
      if (read) entry.lastRead = DateTime.now();
      db.isar.mangaEntrys.putSync(entry);
    });
  }

  static String _prefer(String? fresh, String fallback) =>
      (fresh != null && fresh.trim().isNotEmpty) ? fresh : fallback;

  static String? _preferNullable(String? fresh, String? fallback) =>
      (fresh != null && fresh.trim().isNotEmpty) ? fresh : fallback;
}
