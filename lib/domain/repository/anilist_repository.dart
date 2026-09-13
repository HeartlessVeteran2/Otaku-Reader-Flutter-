import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';

/// Reads AniList metadata for a manga.
///
/// Nothing here writes to the library. AniList data is a **disposable cache
/// with a re-fetchable upstream**; a library row owns the user's data, and a
/// failed refresh must not be able to damage it.
abstract interface class AniListRepository {
  /// Full metadata for one AniList media id.
  Future<AniListMedia?> media(int id);

  /// Searches by title and returns the best candidate with its score.
  ///
  /// Returns the best available even when it is poor — the caller decides using
  /// [TitleMatch.isConfident], because "store it" and "show it" are different
  /// questions from "what came back".
  Future<TitleMatch?> match(String title);

  /// Every candidate for a title, scored and best first.
  ///
  /// Feeds the manual picker, which exists because auto-matching deliberately
  /// refuses anything below the confidence threshold.
  Future<List<TitleMatch>> searchCandidates(String title);

  /// The home page's shelves, keyed by shelf name.
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20});
}
