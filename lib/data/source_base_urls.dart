import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';

/// Resolves the base URL that cover requests should send as `Referer`/`Origin`.
///
/// Three screens need this — library, updates, history — and each had its own
/// copy keyed by source id. One implementation, for two reasons:
///
/// * **The stored `Source.baseUrl` is not necessarily the one in effect.**
///   Sources ship their working mirror as a *declared preference default*, so
///   `SourceMethods.sourceBaseUrl` and the record disagree for a meaningful
///   share of Madara sites. A wrong Referer is a 403, and a grid of fallback
///   covers looks like the app lost them.
/// * **The cache has to be dropped, not just filled.** Updating a source can
///   change its base URL; a map that is only ever added to keeps serving the
///   old one for the life of the process.
///
/// Resolving the effective URL means building the source's runtime, which is
/// not free — but it is cached by `SourceRepository`, so it happens once per
/// source per run, and the very next thing a user does from any of these
/// screens needs that runtime anyway.
class SourceBaseUrls {
  SourceBaseUrls(this._sources);

  final SourceRepository _sources;
  final _cache = <int, String>{};

  /// The URL for [entry]'s source, or '' if it has not been resolved.
  ///
  /// Never resolves on demand: this is read from `build`, once per card, while
  /// the grid is scrolling.
  String forEntry(MangaEntry entry) {
    final id = LibraryRepository.sourceIdOf(entry);
    return id == null ? '' : _cache[id] ?? '';
  }

  /// Re-resolves every source [entries] refer to, discarding what was cached.
  ///
  /// Called at the start of each load rather than filling gaps, so a source
  /// whose base URL changed since the last load is picked up.
  Future<void> refresh(Iterable<MangaEntry> entries) async {
    final ids = <int>{
      for (final entry in entries)
        if (LibraryRepository.sourceIdOf(entry) case final id?) id,
    };
    final resolved = <int, String>{};
    for (final id in ids) {
      resolved[id] = await _resolve(id);
    }
    _cache
      ..clear()
      ..addAll(resolved);
  }

  Future<String> _resolve(int id) async {
    final stored = (await _sources.sourceById(id))?.baseUrl ?? '';
    try {
      final effective = (await _sources.methodsFor(id)).sourceBaseUrl;
      if (effective.isNotEmpty) return effective;
    } catch (_) {
      // An uninstalled or broken source has no runtime to ask. The library can
      // hold entries for one — uninstalling does not delete them — and falling
      // back to the record is strictly better than dropping the header.
    }
    return stored;
  }
}
