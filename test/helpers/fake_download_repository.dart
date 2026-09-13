import 'dart:async';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';

/// A [DownloadRepository] that records calls and downloads nothing.
///
/// Shared, for the same reason `NoSources` is: several suites construct a
/// controller that only needs *a* download repository, and per-suite copies
/// drift apart the moment the interface gains a method.
class FakeDownloads implements DownloadRepository {
  final _changes = StreamController<void>.broadcast();
  final List<String> calls = [];

  /// What [tasks] answers. Set by a test to put the queue in a given state.
  List<DownloadTask> queue = const [];

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<DownloadTask> get tasks => queue;

  /// Publishes a change, as a real download would while it runs.
  void emit() => _changes.add(null);

  @override
  Future<void> enqueue({
    required int sourceId,
    required String mangaUrl,
    required Chapter chapter,
    required String mangaTitle,
  }) async => calls.add('enqueue:${chapter.url}');

  @override
  Future<void> cancel(String key) async => calls.add('cancel:$key');

  @override
  Future<void> deleteChapter({
    required int sourceId,
    required String mangaUrl,
    required String chapterUrl,
  }) async => calls.add('delete:$chapterUrl');

  @override
  void clearFinished() => calls.add('clearFinished');

  @override
  Future<int> usedBytes() async => 0;
}
