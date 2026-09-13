// prefer_initializing_formals wants `this._library`, which Dart does not allow:
// a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/data/source_base_urls.dart';

/// One chapter, read at a point in time.
class HistoryEntry {
  const HistoryEntry({
    required this.entry,
    required this.chapter,
    required this.readAt,
  });

  final MangaEntry entry;
  final Chapter chapter;
  final DateTime readAt;

  /// Identifies the row across a reload, which rebuilds every object.
  String get key => '${entry.sourceId} ${entry.url} ${chapter.url}';
}

/// The reading timeline.
class HistoryController extends GetxController {
  HistoryController({
    required LibraryRepository library,
    required SourceRepository sources,
  }) : _library = library,
       _sources = sources;

  final LibraryRepository _library;
  final SourceRepository _sources;

  /// How long an undo stays available before the delete is committed.
  static const undoWindow = Duration(seconds: 5);

  final entries = <HistoryEntry>[].obs;
  final query = ''.obs;
  final isLoading = false.obs;

  /// Rows hidden from the list while their undo window is open.
  ///
  /// The delete is deferred rather than done-and-reinstated, because putting a
  /// timestamp back means inventing one — the original is gone the moment it
  /// has been written over.
  final _pending = <String>{}.obs;

  Timer? _pendingTimer;
  List<HistoryEntry>? _pendingRows;

  late final _baseUrls = SourceBaseUrls(_sources);

  String baseUrlFor(MangaEntry entry) => _baseUrls.forEntry(entry);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    // Committed rather than cancelled: the user asked for the delete, and the
    // screen closing is not them taking it back.
    unawaited(_commitPending());
    _pendingTimer?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      // Every stored entry, not only favourites: a chapter read from a source
      // and never added to the library is exactly what history is for.
      final all = await _library.allEntries();
      final rows = <HistoryEntry>[];
      for (final entry in all) {
        for (final chapter in entry.chapters) {
          final at = chapter.lastReadTime;
          if (at == null) continue;
          rows.add(
            HistoryEntry(
              entry: entry,
              chapter: chapter,
              readAt: DateTime.fromMillisecondsSinceEpoch(at),
            ),
          );
        }
      }
      rows.sort((a, b) => b.readAt.compareTo(a.readAt));
      entries.value = rows;

      await _baseUrls.refresh(all);
    } finally {
      isLoading.value = false;
    }
  }

  void setQuery(String value) => query.value = value.trim();

  List<HistoryEntry> get visible {
    final q = query.value.toLowerCase();
    return entries
        .where((e) => !_pending.contains(e.key))
        .where(
          (e) => q.isEmpty || e.entry.displayTitle.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Hides [rows] and deletes them once the undo window closes.
  void remove(List<HistoryEntry> rows) {
    if (rows.isEmpty) return;
    // Any batch still pending is committed first, so a second delete's undo
    // cannot reinstate the first delete's rows instead of its own.
    unawaited(_commitPending());
    _pendingRows = rows;
    _pending.addAll(rows.map((r) => r.key));
    _pendingTimer = Timer(undoWindow, () => unawaited(_commitPending()));
  }

  /// Puts the pending batch back. False if it has already committed, which is
  /// what a stale snackbar's undo has to be told.
  bool undo() {
    final rows = _pendingRows;
    if (rows == null) return false;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingRows = null;
    _pending.removeAll(rows.map((r) => r.key));
    return true;
  }

  Future<void> _commitPending() async {
    final rows = _pendingRows;
    if (rows == null) return;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingRows = null;
    for (final row in rows) {
      final sourceId = LibraryRepository.sourceIdOf(row.entry);
      final chapterUrl = row.chapter.url;
      if (sourceId == null || chapterUrl == null) continue;
      await _library.clearChapterHistory(sourceId, row.entry.url, chapterUrl);
    }
    _pending.removeAll(rows.map((r) => r.key));
    await load();
  }

  Future<void> clearAll() async {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingRows = null;
    _pending.clear();
    await _library.clearHistory();
    await load();
  }
}
