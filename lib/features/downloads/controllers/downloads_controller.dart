// prefer_initializing_formals wants `this._downloads`, which Dart does not
// allow: a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/domain/repository/download_repository.dart';

/// The download queue, as a screen sees it.
class DownloadsController extends GetxController {
  DownloadsController({required DownloadRepository downloads})
    : _downloads = downloads;

  final DownloadRepository _downloads;

  final tasks = <DownloadTask>[].obs;
  final usedBytes = 0.obs;

  StreamSubscription<void>? _watch;

  @override
  void onInit() {
    super.onInit();
    _read();
    // The queue outlives this screen — a download started from a details page
    // keeps running after it is popped — so the list is a view of the
    // repository rather than state this controller owns.
    _watch = _downloads.changes.listen((_) => _read());
    unawaited(refreshUsage());
  }

  @override
  void onClose() {
    unawaited(_watch?.cancel());
    super.onClose();
  }

  void _read() {
    tasks.value = _downloads.tasks;
    // Deliberately not recomputed here: walking the download directory is
    // filesystem work, and this fires once per page of every active download.
  }

  /// Counts the scans started, so a slower earlier one cannot land last.
  ///
  /// `onInit` fires one without awaiting it and a pull-to-refresh fires
  /// another, so two walks of the download directory can be in flight at once.
  /// Without this the older one wins whenever it happens to finish second, and
  /// the header shows a figure from before the download that prompted the pull.
  int _scan = 0;

  /// Re-measures what downloads are using. Called on open and on pull.
  Future<void> refreshUsage() async {
    final scan = ++_scan;
    final bytes = await _downloads.usedBytes();
    if (scan != _scan) return;
    usedBytes.value = bytes;
  }

  int get activeCount => tasks
      .where(
        (t) =>
            t.state == DownloadState.queued || t.state == DownloadState.running,
      )
      .length;

  Future<void> cancel(DownloadTask task) => _downloads.cancel(task.key);

  void clearFinished() => _downloads.clearFinished();

  /// Human-readable size. Binary units, because that is what a file manager on
  /// the same device will report and a mismatch reads as a bug.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
