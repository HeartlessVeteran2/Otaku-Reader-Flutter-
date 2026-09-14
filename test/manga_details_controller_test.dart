import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/details/controllers/manga_details_controller.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';

import 'helpers/fake_download_repository.dart';
import 'helpers/isar_test_env.dart';

import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';

import 'helpers/anilist_fakes.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

/// AniList is supplementary, so these tests run without it: every lookup says
/// "no match", which is the same path an obscure title takes in production.
class _NoAniList implements AniListRepository {
  @override
  Future<AniListMedia?> media(int id) async => null;
  @override
  Future<TitleMatch?> match(String title) async => null;
  @override
  Future<List<TitleMatch>> searchCandidates(String title) async => const [];
  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) async =>
      const {};
}

AniListMetadataService _anilistService() =>
    AniListMetadataService(anilist: _NoAniList());

const _sourceId = 7;
const _url = '/manga/example';

class _Methods implements SourceMethods {
  _Methods(this.source, this.detail);

  @override
  final Source source;
  MManga detail;
  Object? failWith;
  int detailCalls = 0;

  /// Responses to hand out in order, each behind a gate the test controls.
  ///
  /// The obvious stub — return the live `detail` field — cannot test the stale
  /// guard at all: `getDetail` is not reached until `_library.find` resolves,
  /// by which time the test has already set the *next* value, so both loads
  /// fetch it and the assertion passes with the guard deleted. Capturing the
  /// response when the call starts, and releasing it when the test says, is
  /// what makes the older response able to land last.
  final List<(MManga, Completer<void>)> scripted = [];

  @override
  Future<MManga> getDetail(String url) async {
    final index = detailCalls++;
    if (index < scripted.length) {
      final (response, gate) = scripted[index];
      await gate.future;
      return response;
    }
    if (failWith != null) throw failWith!;
    return detail;
  }

  @override
  bool get supportsLatest => true;
  @override
  String get sourceBaseUrl => 'https://example.test';
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MPages> getPopular(int p) async => MPages(list: []);
  @override
  Future<MPages> getLatestUpdates(int p) async => MPages(list: []);
  @override
  Future<MPages> search(String q, int p, FilterList f) async =>
      MPages(list: []);
  @override
  Future<List<PageUrl>> getPageList(String url) async => const [];
  @override
  FilterList getFilterList() => FilterList([]);
  @override
  List<SourcePreference> getSourcePreferences() => const [];
  @override
  void dispose() {}
}

class _Sources implements SourceRepository {
  _Sources(this.methods, this.row);
  final _Methods methods;
  final Source row;

  @override
  Future<SourceMethods> methodsFor(int id) async => methods;
  @override
  Future<Source?> sourceById(int id) async => row;
  @override
  Future<void> markUsed(int id) async {}
  @override
  void evict(int id) {}
  @override
  void evictAll() {}
  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => const [];
}

Source _row() => Source()
  ..sourceId = _sourceId
  ..name = 'Example Source'
  ..lang = 'en'
  ..baseUrl = 'https://example.test'
  ..sourceCode = 'X';

MChapter _ch(String url, String name) => MChapter(url: url, name: name);

/// An `AniListListService` whose auth is signed out, so `entryFor` answers null
/// without a request — the state every one of these tests is in.
AniListListService _signedOutList() =>
    AniListListService(AniListAuth(storage: FakeVault(), clientId: ''));

/// Answers the sign-in query at once and then **holds** every later response
/// until released, so two writes can be genuinely in flight at once.
///
/// The split matters: sign-in has to complete for there to be a viewer to
/// write as, and holding it too would make `save` refuse for want of an
/// account rather than for being busy — which is the very distinction under
/// test, and is exactly how the first version of this test lied to itself.
class _HeldClient extends http.BaseClient {
  _HeldClient({required this.signIn, required this.write});

  final String signIn;
  final String write;
  final _gate = Completer<void>();
  int calls = 0;

  void release() => _gate.complete();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    if (calls == 1) return _respond(signIn);
    await _gate.future;
    return _respond(write);
  }

  http.StreamedResponse _respond(String body) => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

String _savedRow() => jsonEncode({
  'data': {
    'SaveMediaListEntry': {
      'id': 9,
      'status': 'CURRENT',
      'progress': 5,
      'score': 0,
      'repeat': 0,
      'private': false,
      'media': {'id': 7},
    },
  },
});

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('details', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  Future<(MangaDetailsController, _Methods)> build(
    MManga detail, {
    MManga? initial,
  }) async {
    final methods = _Methods(_row(), detail);
    final c = MangaDetailsController(
      sources: _Sources(methods, _row()),
      library: library,
      anilist: _anilistService(),
      anilistList: _signedOutList(),
      downloads: FakeDownloads(),
      sourceId: _sourceId,
      url: _url,
      initial: initial,
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return (c, methods);
  }

  test('a concurrent list write is busy, not a refusal by AniList', () async {
    // CodeAnt's finding on #37, and the defect underneath it. The in-flight
    // guard dropped the second write and returned the same `false` as a real
    // refusal, so the screen said "AniList did not save that" about a server
    // that was never asked — a sentence that is simply untrue.
    final held = _HeldClient(signIn: viewerBody(), write: _savedRow());
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: held,
    );
    expect(await auth.signIn('t'), SignInResult.ok);

    final controller = MangaDetailsController(
      sources: _Sources(_Methods(_row(), MManga(name: 'Example')), _row()),
      library: library,
      anilist: _anilistService(),
      anilistList: AniListListService(auth),
      downloads: FakeDownloads(),
      sourceId: _sourceId,
      url: _url,
    );
    controller.anilist.value = const AniListMedia(
      id: 7,
      titles: AniListTitles(userPreferred: 'Example'),
    );

    final first = controller.saveAniList(progress: 5);
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.isSavingAniList.value,
      isTrue,
      reason: 'the first write is genuinely in flight, or this proves nothing',
    );

    final second = await controller.saveAniList(progress: 6);
    expect(
      second,
      AniListSaveResult.busy,
      reason: 'never offered to AniList, so never refused by it',
    );

    held.release();
    expect(await first, AniListSaveResult.ok);
    expect(controller.anilistList.value.entry?.progress, 5);
  });

  test('a save landing after an unlink does not restore the row', () async {
    // CodeAnt's second race on #37. The write is in flight, the user unlinks
    // AniList, and the response then puts back a row for a series the page no
    // longer claims to be — restoring something they just removed.
    //
    // A `_generation` compare, which the load path uses, would miss this
    // exactly: `unlinkAniList` does not bump it. The media id is what
    // identifies what was written.
    final held = _HeldClient(signIn: viewerBody(), write: _savedRow());
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: held,
    );
    await auth.signIn('t');

    final controller = MangaDetailsController(
      sources: _Sources(_Methods(_row(), MManga(name: 'Example')), _row()),
      library: library,
      anilist: _anilistService(),
      anilistList: AniListListService(auth),
      downloads: FakeDownloads(),
      sourceId: _sourceId,
      url: _url,
    );
    controller.anilist.value = const AniListMedia(
      id: 7,
      titles: AniListTitles(userPreferred: 'Example'),
    );

    final pending = controller.saveAniList(progress: 5);
    await Future<void>.delayed(Duration.zero);

    // The page moves on while the write is in flight.
    controller.anilist.value = null;
    controller.anilistList.value = const AniListListResult.signedOut();

    held.release();
    expect(
      await pending,
      AniListSaveResult.ok,
      reason: 'AniList did take the write; only the display is dropped',
    );
    expect(
      controller.anilistList.value.entry,
      isNull,
      reason: 'the row the user removed stays removed',
    );
    expect(controller.anilistList.value.lookup, AniListListLookup.signedOut);
  });

  test(
    'loads the detail and stores it without adding to the library',
    () async {
      final (c, _) = await build(
        MManga(
          name: 'Example',
          author: 'Someone',
          chapters: [_ch('/c-1', 'Chapter 1')],
        ),
      );

      expect(c.entry.value?.title, 'Example');
      expect(c.entry.value?.author, 'Someone');
      expect(c.isFavorite, isFalse);
      expect(await library.favorites(), isEmpty);
    },
  );

  test(
    'chapters sort newest first by default and the order can be flipped',
    () async {
      final (c, _) = await build(
        MManga(
          name: 'Example',
          chapters: [
            _ch('/c-1', 'Chapter 1'),
            _ch('/c-3', 'Chapter 3'),
            _ch('/c-2', 'Chapter 2'),
          ],
        ),
      );

      expect(c.chapters.map((x) => x.number), [3, 2, 1]);

      c.toggleSort();
      expect(c.chapters.map((x) => x.number), [1, 2, 3]);
    },
  );

  test('chapters with no parsable number sort last, not first', () async {
    // Many sources title one-shots and extras by name. Sorting those to the top
    // would bury the actual chapter 1.
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [
          _ch('/extra', 'Extra: Behind the scenes'),
          _ch('/c-1', 'Chapter 1'),
          _ch('/c-2', 'Chapter 2'),
        ],
      ),
    );

    expect(c.chapters.last.url, '/extra');
  });

  test('unnumbered chapters keep source order through an unstable sort', () async {
    // Dart's List.sort only switches to (unstable) quicksort above 32 elements;
    // below that it uses a stable insertion sort. An earlier version of this
    // test used four chapters and therefore passed with the tie-break deleted —
    // green, and proving nothing. 40 unnumbered chapters reach the unstable
    // path, so this now fails without the tie-break.
    // Digit-free titles: the parser reads a number anywhere in a title, so
    // "Extra 7" would parse as chapter 7 and leave nothing to order.
    // Half of them share one url and half have none at all. That is the case
    // the identity-keyed order map exists for: a url-keyed map collapses these
    // onto one entry, putting the tie-break back to returning 0 for exactly
    // the rows it was added to protect — and with distinct urls throughout,
    // the old url-keyed version passed this test too.
    String label(int i) =>
        String.fromCharCode(65 + i ~/ 26) + String.fromCharCode(65 + i % 26);
    final extras = [
      for (var i = 0; i < 40; i++)
        _ch(i.isEven ? '' : '/same', 'Extra ${label(i)}: a side story'),
    ];
    final (c, _) = await build(
      MManga(name: 'Example', chapters: [_ch('/c-1', 'Chapter 1'), ...extras]),
    );

    // Identified by name, since the urls are deliberately not unique.
    final expected = [for (var i = 0; i < 40; i++) 'Extra ${label(i)}'];
    String initials(Iterable<Chapter> rows) =>
        rows.map((x) => (x.name ?? '').split(':').first.trim()).join(',');

    final unnumbered = c.chapters.where((x) => x.number == null).toList();
    expect(unnumbered, hasLength(40), reason: 'none parsed a number');
    expect(initials(unnumbered), expected.join(','));

    // Flipping the numeric direction must not reorder them either.
    c.toggleSort();
    expect(
      initials(c.chapters.where((x) => x.number == null)),
      expected.join(','),
    );
  });

  test('a stale load cannot overwrite a newer one', () async {
    // A pull-to-refresh started before the first load returns must not let the
    // older response land last -- so the older one is deliberately released
    // *after* the newer one has already finished.
    final (c, methods) = await build(MManga(name: 'First'));
    expect(c.entry.value?.title, 'First');

    final slowGate = Completer<void>();
    final fastGate = Completer<void>()..complete();
    methods
      ..detailCalls = 0
      ..scripted.addAll([
        (MManga(name: 'Second'), slowGate),
        (MManga(name: 'Third'), fastGate),
      ]);

    final slow = c.load();
    await Future<void>.delayed(Duration.zero);
    await c.load();
    expect(c.entry.value?.title, 'Third');

    slowGate.complete();
    await slow;

    expect(
      c.entry.value?.title,
      'Third',
      reason: 'the superseded response was dropped, not applied last',
    );
  });

  test('the unread filter hides read chapters and the count follows', () async {
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1', 'Chapter 1'), _ch('/c-2', 'Chapter 2')],
      ),
    );
    expect(c.unreadCount, 2);

    await c.setRead(c.chapters.last, true); // chapter 1

    expect(c.unreadCount, 1);
    c.setFilter(ChapterFilter.unread);
    expect(c.chapters.map((x) => x.number), [2]);
  });

  test('mark-read-up-to sets everything at or below that chapter', () async {
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [
          _ch('/c-1', 'Chapter 1'),
          _ch('/c-2', 'Chapter 2'),
          _ch('/c-3', 'Chapter 3'),
          _ch('/c-4', 'Chapter 4'),
        ],
      ),
    );

    final chapterThree = c.chapters.firstWhere((x) => x.number == 3);
    await c.markReadUpTo(chapterThree);

    final read = {for (final x in c.chapters) x.number: x.read};
    expect(read, {4.0: false, 3.0: true, 2.0: true, 1.0: true});
  });

  test('toggling favorite persists', () async {
    final (c, _) = await build(MManga(name: 'Example'));

    await c.toggleFavorite();

    expect(c.isFavorite, isTrue);
    expect((await library.favorites()).single.url, _url);
  });

  test(
    'a stored entry plus a failed refresh is a usable page, not an error',
    () async {
      // Reopening a manga you have read must work offline.
      final (first, _) = await build(
        MManga(name: 'Example', chapters: [_ch('/c-1', 'Chapter 1')]),
      );
      expect(first.entry.value, isNotNull);

      final methods = _Methods(_row(), MManga())
        ..failWith = StateError('offline');
      final second = MangaDetailsController(
        sources: _Sources(methods, _row()),
        library: library,
        anilist: _anilistService(),
        anilistList: _signedOutList(),
        downloads: FakeDownloads(),
        sourceId: _sourceId,
        url: _url,
      )..onInit();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(second.error.value, isNull, reason: 'there is something to show');
      expect(second.entry.value?.title, 'Example');
      expect(second.chapters, hasLength(1));
    },
  );

  test('a first visit that fails does report an error', () async {
    final methods = _Methods(_row(), MManga())..failWith = StateError('502');
    final c = MangaDetailsController(
      sources: _Sources(methods, _row()),
      library: library,
      anilist: _anilistService(),
      anilistList: _signedOutList(),
      downloads: FakeDownloads(),
      sourceId: _sourceId,
      url: _url,
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(c.error.value, contains('site may be down'));
    expect(c.isLoading.value, isFalse);
  });

  test('favorite is refused when there is no row to favourite', () async {
    final methods = _Methods(_row(), MManga())..failWith = StateError('502');
    final c = MangaDetailsController(
      sources: _Sources(methods, _row()),
      library: library,
      anilist: _anilistService(),
      anilistList: _signedOutList(),
      downloads: FakeDownloads(),
      sourceId: _sourceId,
      url: _url,
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await c.toggleFavorite(); // must not throw

    expect(c.isFavorite, isFalse);
  });

  test(
    'the preview from the grid is available before the detail lands',
    () async {
      final preview = MManga(
        name: 'From the grid',
        imageUrl: 'https://c/i.jpg',
      );
      final (c, _) = await build(MManga(name: 'Example'), initial: preview);

      expect(c.preview?.name, 'From the grid');
    },
  );
  test('a write from elsewhere refreshes the chapter list', () async {
    // The reader writes progress on a debounce and flushes it from its own
    // `onClose`, which cannot be awaited — so the details page's own
    // `refreshEntry()` on the way back can win that race. Reacting to the write
    // closes it without depending on the ordering.
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1', 'Chapter 1'), _ch('/c-2', 'Chapter 2')],
      ),
    );
    expect(c.unreadCount, 2);

    // A write through the repository, as a closing reader would make.
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _url,
      chapterUrl: '/c-1',
      lastPageRead: 9,
      totalPages: 10,
      markRead: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(c.unreadCount, 1);
    c.onClose();
  });
}
