// prefer_initializing_formals wants `this._anilist`, which Dart does not allow:
// a named parameter cannot be private. The field stays private so call sites
// cannot reach past this service to the repository it mediates.
// ignore_for_file: prefer_initializing_formals

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';

/// Resolves a library row to AniList metadata, and caches it.
///
/// Two pieces of state, deliberately separate:
///
/// * **The link** — which AniList media this manga is. Written only for a
///   confident auto-match, or by the user picking one. It must outlive the
///   cache, because a user's correction is not disposable.
/// * **The metadata** — a cache with a re-fetchable upstream and a TTL. A
///   refetch overwrites it wholesale.
///
/// Nothing here touches the library row. AniList is supplementary; a failed
/// lookup must not be able to damage the user's data.
class AniListMetadataService {
  AniListMetadataService({required AniListRepository anilist})
    : _anilist = anilist;

  final AniListRepository _anilist;

  /// How long a cached payload is served before refetching.
  ///
  /// AniList metadata changes slowly — scores drift, a relation is added — and
  /// the page must open instantly offline, so a week is generous rather than
  /// stingy.
  static const ttl = Duration(days: 7);

  /// The stored AniList id for a library row, if any.
  int? linkFor(int entryId) => DynamicKeys.anilistLink.get<int?>(entryId);

  /// Records a user's explicit choice, and drops the cached payload so the new
  /// id is fetched rather than the old one being shown under a new link.
  void setLink(int entryId, int anilistId) {
    DynamicKeys.anilistLink.set<int>(entryId, anilistId);
    DynamicKeys.anilistMeta.delete(entryId);
    DynamicKeys.anilistMetaAt.delete(entryId);
  }

  void clearLink(int entryId) {
    DynamicKeys.anilistLink.delete(entryId);
    DynamicKeys.anilistMeta.delete(entryId);
    DynamicKeys.anilistMetaAt.delete(entryId);
  }

  /// Metadata for [entryId], from cache when fresh.
  ///
  /// Returns null when nothing is linked and nothing confident can be matched —
  /// which is the correct outcome, not a failure. **A wrong synopsis and wrong
  /// tags look exactly as authoritative as right ones**, so below the
  /// confidence threshold nothing is stored and nothing renders; the recourse
  /// is the manual picker, not a lower bar.
  Future<AniListMedia?> metadataFor({
    required int entryId,
    required String title,
    bool forceRefresh = false,
  }) async {
    final cached = forceRefresh ? null : _cached(entryId);
    if (cached != null) return cached;

    var anilistId = linkFor(entryId);
    if (anilistId == null) {
      final match = await _anilist.match(title);
      if (match == null || !match.isConfident) return null;
      anilistId = match.media.id;
      // Only a confident auto-match is persisted. An uncertain one is not
      // written at all, so the next open tries again rather than inheriting a
      // guess nobody can see was a guess.
      DynamicKeys.anilistLink.set<int>(entryId, anilistId);
    }

    final media = await _anilist.media(anilistId);
    if (media == null) return _cached(entryId, ignoreTtl: true);

    DynamicKeys.anilistMeta.set<Map<String, dynamic>>(entryId, media.raw);
    DynamicKeys.anilistMetaAt.set<int>(
      entryId,
      DateTime.now().millisecondsSinceEpoch,
    );
    return media;
  }

  /// The cached payload, or null when absent or stale.
  ///
  /// [ignoreTtl] serves a stale copy rather than nothing when the network
  /// failed: out-of-date scores beat an empty page.
  AniListMedia? _cached(int entryId, {bool ignoreTtl = false}) {
    final raw = DynamicKeys.anilistMeta.get<Map<String, dynamic>?>(entryId);
    if (raw == null) return null;
    if (!ignoreTtl) {
      final at = DynamicKeys.anilistMetaAt.get<int?>(entryId);
      if (at == null) return null;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(at),
      );
      if (age > ttl) return null;
    }
    return AniListMedia.fromJson(raw);
  }

  /// Candidates for the manual picker, best first.
  Future<List<TitleMatch>> candidates(String title) =>
      _anilist.searchCandidates(title);
}
