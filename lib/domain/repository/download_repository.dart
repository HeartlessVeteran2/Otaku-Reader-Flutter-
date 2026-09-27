import 'package:otaku_reader/data/isar/manga_entry.dart';

/// The image extensions a downloaded page can have on disk.
///
/// Shared, because the two sides have to agree: the downloader normalises
/// every page url to one of these, and the reader shows only files that match.
/// Held apart, adding a format to the downloader would make those pages
/// invisible to the reader with nothing failing to say so.
const kDownloadedPageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.avif',
};

/// Where a chapter is in the download pipeline.
enum DownloadState {
  /// Not downloaded and not queued.
  none,

  /// Waiting for a slot.
  queued,

  /// Pages are being fetched.
  running,

  /// Every page is on disk and [Chapter.localPath] points at them.
  done,

  /// It stopped part-way. Nothing readable was left behind.
  failed,
}

/// One chapter's download, as the UI sees it.
class DownloadTask {
  const DownloadTask({
    required this.sourceId,
    required this.mangaUrl,
    required this.chapterUrl,
    required this.title,
    required this.chapterLabel,
    required this.state,
    this.downloaded = 0,
    this.total = 0,
    this.error,
  });

  final int sourceId;
  final String mangaUrl;
  final String chapterUrl;

  /// For display only — the queue outlives the screen that started it.
  final String title;
  final String chapterLabel;

  final DownloadState state;
  final int downloaded;
  final int total;
  final String? error;

  /// 0..1, or null while the page count is still unknown.
  double? get progress => total == 0 ? null : downloaded / total;

  String get key => '$sourceId $mangaUrl $chapterUrl';
}

/// Downloads chapters for offline reading.
///
/// The contract that matters is **a chapter is downloaded or it is not**.
/// There is no half-downloaded state a reader can open: pages land in a
/// temporary directory and are moved into place as one step, and
/// `Chapter.localPath` is written only after that move. An interrupted
/// download leaves nothing that anything will read.
abstract interface class DownloadRepository {
  /// Emits whenever any task changes, so a screen can re-read [tasks].
  Stream<void> get changes;

  /// The queue, newest first. Includes finished and failed entries until they
  /// are cleared — a failure the user never sees is a chapter that silently
  /// never downloaded.
  List<DownloadTask> get tasks;

  /// Queues [chapter] of the manga at (`sourceId`, `mangaUrl`).
  ///
  /// A chapter already queued, running or done is a no-op: the button is a
  /// toggle, and re-queuing would re-fetch pages that are already on disk.
  Future<void> enqueue({
    required int sourceId,
    required String mangaUrl,
    required Chapter chapter,
    required String mangaTitle,
  });

  /// Removes a queued task, or stops a running one at the next page boundary.
  Future<void> cancel(String key);

  /// Deletes the files and clears `Chapter.localPath`.
  ///
  /// Read state is untouched: deleting a download frees space, it does not
  /// mean the chapter was not read.
  Future<void> deleteChapter({
    required int sourceId,
    required String mangaUrl,
    required String chapterUrl,
  });

  /// Whether pending tasks are being held back waiting for an unmetered
  /// connection.
  ///
  /// A property of the **queue**, not of a task, and that is the whole reason
  /// it is not a [DownloadState]. Every pending task is held by the same one
  /// fact, so a per-task state would write the same answer onto N rows and
  /// clear it again on every connectivity event, and the screen would render N
  /// identical rows each explaining the same thing. One flag renders one
  /// banner. The distinction it buys is the one `UpdateDecision` already
  /// makes: "waiting for Wi-Fi" is something the reader can act on, where a
  /// queue that merely sits still reads as broken.
  bool get heldForWifi;

  /// Drops finished and failed entries from the queue. Files are kept.
  void clearFinished();

  /// Total bytes currently held by downloads.
  Future<int> usedBytes();

  /// Releases the connectivity subscription.
  ///
  /// The app holds one of these for its whole life, so this exists for tests
  /// rather than for production — but a listener with no way to be cancelled
  /// is how a suite ends up with one test's repository reacting to another
  /// test's connectivity event.
  void dispose();
}
