// prefer_initializing_formals wants `this._library`, which Dart does not allow:
// a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/core/platform/network_status.dart';
import 'package:otaku_reader/data/source_base_urls.dart';
import 'package:otaku_reader/features/updates/scheduling/update_schedule.dart';
import 'package:otaku_reader/source/model/m_status.dart';

/// One new chapter, with the manga it belongs to.
class ChapterUpdate {
  const ChapterUpdate({
    required this.entry,
    required this.chapter,
    required this.fetchedAt,
  });

  final MangaEntry entry;
  final Chapter chapter;
  final DateTime fetchedAt;
}

/// A manga whose refresh failed, and why.
///
/// Kept and shown rather than swallowed: a source that has moved domain fails
/// every refresh silently otherwise, and the only symptom is a series that
/// quietly stops getting chapters.
class UpdateError {
  const UpdateError({required this.entry, required this.message});

  final MangaEntry entry;
  final String message;
}

/// The Updates tab: chapters that appeared after the app already knew a series.
class UpdatesController extends GetxController {
  UpdatesController({
    required LibraryRepository library,
    required SourceRepository sources,
    required NetworkStatus network,
  }) : _library = library,
       _sources = sources,
       _network = network;

  final LibraryRepository _library;
  final SourceRepository _sources;

  /// Whether the connection is one to crawl every installed source over.
  ///
  /// Required rather than optional for the same reason the reader's wakelock
  /// is: an optional dependency lets a call site forget it, and the switch in
  /// front of it goes quietly dead — which is the exact defect this slice
  /// exists to close.
  final NetworkStatus _network;

  /// How many series are refreshed at once. Same reasoning as global search:
  /// one request per library entry would be hundreds of connections at once,
  /// and rate-limiting is how a site answers that.
  static const _concurrency = 3;

  final updates = <ChapterUpdate>[].obs;
  final errors = <UpdateError>[].obs;
  final isLoading = false.obs;
  final isRefreshing = false.obs;

  /// How far through a refresh we are, for the progress line.
  final done = 0.obs;
  final total = 0.obs;

  final lastChecked = Rxn<DateTime>();

  /// Source base URLs, for the cover requests' Referer and Origin. Cached per
  /// load rather than resolved per tile, because every tile rebuilds on scroll.
  late final _baseUrls = SourceBaseUrls(_sources);

  String baseUrlFor(MangaEntry entry) => _baseUrls.forEntry(entry);

  @override
  void onInit() {
    super.onInit();
    final stored = UpdateKeys.lastUpdateCheck.get<int?>(null);
    if (stored != null) {
      lastChecked.value = DateTime.fromMillisecondsSinceEpoch(stored);
    }
    load();
    _startWatching();
  }

  @override
  void onClose() {
    _watchDebounce?.cancel();
    unawaited(_watch?.cancel());
    super.onClose();
  }

  /// Reloads when the library changes anywhere else in the app.
  ///
  /// The tabs live in an `IndexedStack` and stay mounted, so no lifecycle hook
  /// fires when one is reselected — favouriting from Browse left this stale
  /// until the app restarted, and `didChangeDependencies` was a fix for a
  /// different case (a fresh push) that looked like a fix for this one.
  ///
  /// Debounced, because a library refresh writes once per series and this would
  /// otherwise reload once per write.
  StreamSubscription<void>? _watch;
  Timer? _watchDebounce;

  void _startWatching() {
    _watch = _library.changes.listen((_) {
      _watchDebounce?.cancel();
      _watchDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(load()),
      );
    });
  }

  /// How many listed updates are still unread — the bottom bar's badge.
  ///
  /// Derived rather than stored, so marking one read from any screen moves the
  /// badge without a second source of truth to keep in step.
  int get unreadCount => updates.where((u) => !u.chapter.read).length;

  /// Reads what is already stored. No network.
  Future<void> load() async {
    isLoading.value = true;
    try {
      final favourites = await _library.favorites();
      final rows = <ChapterUpdate>[];
      for (final entry in favourites) {
        for (final chapter in entry.chapters) {
          final at = chapter.dateFetch;
          if (at == null) continue;
          rows.add(
            ChapterUpdate(
              entry: entry,
              chapter: chapter,
              fetchedAt: DateTime.fromMillisecondsSinceEpoch(at),
            ),
          );
        }
      }
      rows.sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
      updates.value = rows;

      await _baseUrls.refresh(favourites);
    } finally {
      isLoading.value = false;
    }
  }

  /// Refreshes every favourite against its source, then reloads the list.
  ///
  /// Not named `refresh`: `GetxController` already has one, from the notifier
  /// mixin, and GetX calls it internally to rebuild listeners. Shadowing it
  /// with a library-wide network fetch would fire a full refresh every time
  /// the framework wanted a repaint.
  /// Refreshes only if the schedule says it is due.
  ///
  /// Separate from [refreshLibrary], which is what the pull-to-refresh calls
  /// and must always run: a gesture is the user asking, and silently ignoring
  /// it because an interval has not elapsed is the feature deciding it knows
  /// better. This one is for launch and resume.
  ///
  /// Returns the decision so a caller can render *why* nothing happened —
  /// "waiting for Wi-Fi" is something a user can act on, and collapsing it
  /// into "nothing to do" makes a working feature look broken.
  Future<UpdateDecision> refreshIfDue({DateTime? now}) async {
    final interval =
        UpdateInterval.values[UpdateKeys.updateInterval
            .get<int>(UpdateInterval.manual.index)
            .clamp(0, UpdateInterval.values.length - 1)];
    final wifiOnly = UpdateKeys.updateOnWifiOnly.get<bool>(true);

    // The network is only asked about when the schedule has already said yes.
    // Querying a platform channel on every resume to answer a question that
    // usually ends in "not due" is work nobody asked for.
    final provisional = shouldRefreshLibrary(
      interval: interval,
      lastCheck: lastChecked.value,
      now: now ?? DateTime.now(),
      wifiOnly: false,
      onWifi: true,
    );
    if (!provisional.shouldRun) return provisional;

    final decision = shouldRefreshLibrary(
      interval: interval,
      lastCheck: lastChecked.value,
      now: now ?? DateTime.now(),
      wifiOnly: wifiOnly,
      onWifi: wifiOnly ? await _network.isUnmetered() : true,
    );
    if (!decision.shouldRun) return decision;

    await refreshLibrary();
    return UpdateDecision.run;
  }

  /// Whether a series is still getting chapters.
  ///
  /// A finished series is the bulk of a long-lived library and will never gain
  /// anything, so refreshing it is a request per entry per interval spent on a
  /// guaranteed no. `unknown` counts as ongoing on purpose: most sources do not
  /// report status at all, and treating "I don't know" as finished would
  /// silently stop updating most of the library.
  static bool isOngoing(MangaEntry entry) {
    final status =
        Status.values[entry.status.clamp(0, Status.values.length - 1)];
    return status != Status.completed &&
        status != Status.canceled &&
        status != Status.publishingFinished;
  }

  Future<void> refreshLibrary() async {
    if (isRefreshing.value) return;
    isRefreshing.value = true;
    errors.clear();
    done.value = 0;
    try {
      final all = await _library.favorites();
      // Filtered here rather than inside the worker, so the progress line
      // counts what will actually be fetched. Counting skipped entries as
      // "done" makes a refresh of 200 finished series look like it did work.
      final favourites = UpdateKeys.updateOnlyOngoing.get<bool>(false)
          ? all.where(isOngoing).toList()
          : all;
      total.value = favourites.length;

      var next = 0;
      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= favourites.length) return;
          await _refreshOne(favourites[i]);
          done.value++;
        }
      }

      await Future.wait([
        for (var i = 0; i < _concurrency && i < favourites.length; i++)
          worker(),
      ]);

      final now = DateTime.now();
      UpdateKeys.lastUpdateCheck.set<int>(now.millisecondsSinceEpoch);
      lastChecked.value = now;
      await load();
    } finally {
      isRefreshing.value = false;
      total.value = 0;
      done.value = 0;
    }
  }

  Future<void> _refreshOne(MangaEntry entry) async {
    final sourceId = LibraryRepository.sourceIdOf(entry);
    if (sourceId == null) {
      errors.add(
        UpdateError(entry: entry, message: 'This entry has no usable source'),
      );
      return;
    }
    try {
      final methods = await _sources.methodsFor(sourceId);
      final manga = await methods.getDetail(entry.url);
      await _library.upsertFromSource(
        sourceId: sourceId,
        url: entry.url,
        manga: manga,
      );
    } catch (e) {
      // One failing series must not stop the rest of the library from
      // refreshing, which is why this catches per entry rather than per run.
      errors.add(UpdateError(entry: entry, message: _describe(e)));
    }
  }

  Future<void> markRead(ChapterUpdate update, bool read) async {
    final sourceId = LibraryRepository.sourceIdOf(update.entry);
    final chapterUrl = update.chapter.url;
    if (sourceId == null || chapterUrl == null) return;
    await _library.setChapterRead(sourceId, update.entry.url, chapterUrl, read);
    update.chapter.read = read;
    updates.refresh();
  }

  Future<void> markAllRead() async {
    for (final update in [...updates]) {
      if (!update.chapter.read) await markRead(update, true);
    }
  }

  static String _describe(Object error) {
    final text = '$error';
    // Every hard failure in this project's own live sweep was external -- a
    // dead domain, a 301, a TLS refusal. A message implying the app is broken
    // sends the user to the wrong place.
    if (text.contains('SocketException') ||
        text.contains('HandshakeException') ||
        text.contains('TimeoutException')) {
      return 'Could not reach the site';
    }
    return text;
  }
}
