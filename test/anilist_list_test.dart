import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';
import 'package:otaku_reader/features/details/widgets/anilist_sections.dart';

import 'helpers/anilist_fakes.dart';

String _listBody({
  String status = 'CURRENT',
  int progress = 12,
  Object? score = 8.5,
  int repeat = 0,
  bool private = false,
}) => jsonEncode({
  'data': {
    'MediaList': {
      'id': 99,
      'status': status,
      'progress': progress,
      'progressVolumes': 2,
      'score': score,
      'repeat': repeat,
      'private': private,
      'media': {'id': 7},
    },
  },
});

void main() {
  group('reading the viewer\'s own list row', () {
    test('signed out asks AniList nothing', () async {
      // Not merely "returns null": a signed-out user has no list, so a request
      // would be an anonymous query answered with an error, on every details
      // page they open.
      final sent = <http.Request>[];
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: FakeClient(_listBody(), sent: sent),
      );
      await auth.restore();

      expect(await AniListListService(auth).entryFor(7), isNull);
      expect(sent, isEmpty);
    });

    test('a restored-but-unverified token asks nothing either', () async {
      // The state the service's own guard is actually for, and the one the
      // signed-out test above does *not* cover: `AniListAuth.query` already
      // refuses when there is no token, so that test passes with this guard
      // deleted. An offline launch keeps the stored token — deliberately —
      // and leaves `viewer` null, so `isSignedIn` is true while there is no
      // user id to query by.
      final sent = <http.Request>[];
      final auth = AniListAuth(
        storage: FakeVault()..store['anilist_access_token'] = 'good',
        clientId: 'abc',
        client: FakeClient.offline(sent: sent),
      );
      await auth.restore();
      expect(
        auth.isSignedIn,
        isTrue,
        reason: 'the token survives being offline',
      );
      expect(auth.viewer.value, isNull);
      sent.clear();

      expect(await AniListListService(auth).entryFor(7), isNull);
      expect(sent, isEmpty);
    });

    test('a row comes back with status, progress and score', () async {
      final live = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([viewerBody(), _listBody()]),
      );
      await live.signIn('t');

      final entry = await AniListListService(live).entryFor(7);

      expect(entry?.status, AniListListStatus.current);
      expect(entry?.statusLabel, 'Reading');
      expect(entry?.progress, 12);
      expect(entry?.score, 8.5);
      expect(entry?.mediaId, 7);
    });

    test('a score of zero is unscored, not a rating of zero', () async {
      // AniList stores no "unset" — every format bottoms out at 0 — so taking
      // the number at face value would stamp a rating of zero on every entry
      // the user has never rated, which is most of them.
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([viewerBody(), _listBody(score: 0)]),
      );
      await auth.signIn('t');

      final entry = await AniListListService(auth).entryFor(7);

      expect(
        entry,
        isNotNull,
        reason: 'the row exists; only the score does not',
      );
      expect(entry?.score, isNull);
    });

    test('the query asks for the viewer\'s own score format', () async {
      // The schema takes `score(format: ScoreFormat)`. Leaving it off would
      // show a five-star user a ten-point number their profile never displays.
      final sent = <http.Request>[];
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([
          viewerBody(format: 'POINT_5'),
          _listBody(score: 4),
        ], sent: sent),
      );
      await auth.signIn('t');

      await AniListListService(auth).entryFor(7);

      final body = jsonDecode(sent.last.body) as Map<String, dynamic>;
      expect((body['variables'] as Map)['format'], 'POINT_5');
      expect(body['query'], contains(r'score(format: $format)'));
      expect(
        body['query'],
        contains('type: MANGA'),
        reason: 'a media id shared with an anime must not resolve to it',
      );
    });

    test('an unknown status is shown, not mislabelled as reading', () async {
      // AniList adding a status must not make the row claim the user is
      // reading something they are not.
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([viewerBody(), _listBody(status: 'ARCHIVED')]),
      );
      await auth.signIn('t');

      final entry = await AniListListService(auth).entryFor(7);

      expect(entry?.status, isNull);
      expect(entry?.statusLabel, 'Archived');
    });

    test('a malformed row is no row, not a crash', () async {
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([
          viewerBody(),
          jsonEncode({
            'data': {
              'MediaList': {'id': 'ninety-nine'},
            },
          }),
        ]),
      );
      await auth.signIn('t');

      expect(await AniListListService(auth).entryFor(7), isNull);
    });
  });

  group('the row on the details page', () {
    Future<void> show(WidgetTester tester, AniListListEntry? entry) =>
        tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorSchemeSeed: Colors.indigo),
            home: Scaffold(
              body: AniListListRow(entry: entry, totalChapters: 24),
            ),
          ),
        );

    testWidgets('no row renders nothing at all', (tester) async {
      await show(tester, null);
      expect(tester.takeException(), isNull);
      expect(find.text('On your AniList'), findsNothing);
    });

    testWidgets('a row renders status, progress and score', (tester) async {
      await show(
        tester,
        const AniListListEntry(
          id: 1,
          mediaId: 7,
          status: AniListListStatus.current,
          statusRaw: 'CURRENT',
          progress: 12,
          score: 8.5,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('On your AniList'), findsOneWidget);
      expect(find.textContaining('Reading'), findsOneWidget);
      expect(find.textContaining('Ch. 12 / 24'), findsOneWidget);
      expect(find.textContaining('★ 8.5'), findsOneWidget);
    });

    testWidgets('an unscored row shows no rating', (tester) async {
      // The rendered half of the zero-is-unscored rule: a "★ 0" on the page
      // is what the model guard exists to prevent.
      await show(
        tester,
        const AniListListEntry(
          id: 1,
          mediaId: 7,
          status: AniListListStatus.planning,
          statusRaw: 'PLANNING',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('★'), findsNothing);
      expect(find.textContaining('Planning'), findsOneWidget);
    });

    testWidgets('a whole score drops its pointless decimal', (tester) async {
      await show(
        tester,
        const AniListListEntry(id: 1, mediaId: 7, progress: 3, score: 8),
      );
      expect(find.textContaining('★ 8'), findsOneWidget);
      expect(find.textContaining('★ 8.0'), findsNothing);
    });
  });
}

/// Answers a different body per request, so a sign-in and the list query that
/// follows it can return different things through one client.
class _SequencedClient extends http.BaseClient {
  _SequencedClient(this._bodies, {this.sent});

  final List<String> _bodies;
  final List<http.Request>? sent;
  int _calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    sent?.add(
      http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..body = body,
    );
    final index = _calls < _bodies.length ? _calls : _bodies.length - 1;
    _calls++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(_bodies[index])),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}
