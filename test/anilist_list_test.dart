import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';
import 'package:otaku_reader/features/details/widgets/anilist_sections.dart';

import 'helpers/anilist_fakes.dart';

import 'package:iconsax/iconsax.dart';

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

String _savedBody({String status = 'CURRENT', int progress = 12}) =>
    jsonEncode({
      'data': {
        'SaveMediaListEntry': {
          'id': 99,
          'status': status,
          'progress': progress,
          'progressVolumes': 2,
          'score': 8.5,
          'repeat': 0,
          'private': false,
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

      expect(
        (await AniListListService(auth).lookUp(7)).lookup,
        AniListListLookup.signedOut,
      );
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

      expect(
        (await AniListListService(auth).lookUp(7)).lookup,
        AniListListLookup.signedOut,
      );
      expect(sent, isEmpty);
    });

    test('a row comes back with status, progress and score', () async {
      final live = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([viewerBody(), _listBody()]),
      );
      await live.signIn('t');

      final entry = (await AniListListService(live).lookUp(7)).entry;

      expect(entry?.status, AniListListStatus.current);
      expect(entry?.statusLabel, 'Reading');
      expect(entry?.progress, 12);
      expect(entry?.score, 8.5);
      expect(entry?.mediaId, 7);
    });

    test('a successful reply with no row means not on the list', () async {
      // The distinction the whole four-state design rests on. AniList answers
      // a perfectly good query with `MediaList: null` when the user simply
      // does not track this series — and that is the one state where the UI
      // offers to add it.
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([
          viewerBody(),
          jsonEncode({
            'data': {'MediaList': null},
          }),
        ]),
      );
      await auth.signIn('t');

      final result = await AniListListService(auth).lookUp(7);

      expect(result.lookup, AniListListLookup.notOnList);
      expect(result.isActionable, isTrue);
    });

    test('a failed call is unavailable, not "not on the list"', () async {
      // The other half, and the reason these cannot be collapsed: offering to
      // add a series while AniList is unreachable offers an action that is
      // about to fail.
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([viewerBody(), '<html>502</html>']),
      );
      await auth.signIn('t');

      final result = await AniListListService(auth).lookUp(7);

      expect(result.lookup, AniListListLookup.unavailable);
      expect(result.isActionable, isFalse);
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

      final entry = (await AniListListService(auth).lookUp(7)).entry;

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

      await AniListListService(auth).lookUp(7);

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

      final entry = (await AniListListService(auth).lookUp(7)).entry;

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

      expect((await AniListListService(auth).lookUp(7)).entry, isNull);
    });
  });

  group('writing the list back', () {
    Future<AniListAuth> signedIn(
      List<String> bodies,
      List<http.Request> sent,
    ) async {
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: _SequencedClient([viewerBody(), ...bodies], sent: sent),
      );
      await auth.signIn('t');
      sent.clear();
      return auth;
    }

    test('only the fields that changed are sent', () async {
      // The rule that matters most here. AniList writes exactly what it is
      // given, so sending a field the user never touched writes back a value
      // read minutes ago — quietly undoing progress they made on another
      // device in between.
      final sent = <http.Request>[];
      final auth = await signedIn([_savedBody(status: 'COMPLETED')], sent);

      await AniListListService(auth)
          .save(mediaId: 7, status: AniListListStatus.completed);

      final vars =
          (jsonDecode(sent.single.body) as Map<String, dynamic>)['variables']
              as Map<String, dynamic>;
      expect(vars['status'], 'COMPLETED');
      expect(
        vars.containsKey('progress'),
        isFalse,
        reason: 'untouched means absent, not zero',
      );
      expect(vars['mediaId'], 7);
    });

    test('a zero progress is still sent, because zero is a choice', () async {
      // The opposite trap to the one above: "leave it alone" is null, and 0 is
      // a real value a user can set by stepping back to the start. Treating
      // falsy as absent would make that edit silently do nothing.
      final sent = <http.Request>[];
      final auth = await signedIn([_savedBody(progress: 0)], sent);

      await AniListListService(auth).save(mediaId: 7, progress: 0);

      final vars =
          (jsonDecode(sent.single.body) as Map<String, dynamic>)['variables']
              as Map<String, dynamic>;
      expect(vars['progress'], 0);
    });

    test('an empty edit is not sent at all', () async {
      final sent = <http.Request>[];
      final auth = await signedIn([_savedBody()], sent);

      expect(await AniListListService(auth).save(mediaId: 7), isNull);
      expect(sent, isEmpty);
    });

    test('signed out writes nothing', () async {
      final sent = <http.Request>[];
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: FakeClient(_savedBody(), sent: sent),
      );
      await auth.restore();

      expect(
        await AniListListService(auth)
            .save(mediaId: 7, status: AniListListStatus.completed),
        isNull,
      );
      expect(sent, isEmpty);
    });

    test('the row comes back from the response, not from the request', () async {
      // AniList may normalise what it was sent — completing a series bumps
      // progress to the chapter count, for one. Echoing the request back would
      // show the user a number the server does not hold.
      final sent = <http.Request>[];
      final auth = await signedIn([
        _savedBody(status: 'COMPLETED', progress: 24),
      ], sent);

      final saved = await AniListListService(auth)
          .save(mediaId: 7, status: AniListListStatus.completed);

      expect(saved?.status, AniListListStatus.completed);
      expect(
        saved?.progress,
        24,
        reason: 'the server moved it; the request said nothing about progress',
      );
    });

    test('a refused write answers null rather than pretending', () async {
      final sent = <http.Request>[];
      final auth = await signedIn([
        jsonEncode({
          'errors': [
            {'message': 'Too many requests'},
          ],
        }),
      ], sent);

      expect(
        await AniListListService(auth).save(mediaId: 7, progress: 3),
        isNull,
      );
    });
  });

  group('the row while a write is in flight', () {
    Future<void> show(
      WidgetTester tester, {
      required bool isSaving,
      VoidCallback? onEdit,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: AniListListRow(
            result: const AniListListResult(
              AniListListLookup.onList,
              AniListListEntry(id: 1, mediaId: 7, progress: 12),
            ),
            totalChapters: 24,
            isSaving: isSaving,
            onEdit: onEdit,
          ),
        ),
      ),
    );

    testWidgets('a null callback really disables the tap target', (
      tester,
    ) async {
      // Asserting a counter stayed at zero while passing no callback proves
      // nothing — nothing could have incremented it. What is falsifiable is
      // that the row wires the callback straight through, so a null one
      // leaves `InkWell.onTap` null rather than the row inventing a handler.
      await show(tester, isSaving: true, onEdit: null);

      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a saving row says it is busy rather than going dead', (
      tester,
    ) async {
      // A tap target that silently stops responding reads as broken. The
      // spinner is what makes the disabled state legible.
      await show(tester, isSaving: true, onEdit: null);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Iconsax.edit_2), findsNothing);
    });

    testWidgets('an idle row offers the edit affordance', (tester) async {
      var taps = 0;
      await show(tester, isSaving: false, onEdit: () => taps++);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Iconsax.edit_2), findsOneWidget);

      await tester.tap(find.byType(AniListListRow));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('the row on the details page', () {
    Future<void> show(
      WidgetTester tester,
      AniListListResult result, {
      VoidCallback? onEdit,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: AniListListRow(
            result: result,
            totalChapters: 24,
            onEdit: onEdit,
          ),
        ),
      ),
    );

    testWidgets('signed out renders nothing at all', (tester) async {
      await show(tester, const AniListListResult.signedOut());
      expect(tester.takeException(), isNull);
      expect(find.text('On your AniList'), findsNothing);
      expect(find.text('Add to your AniList'), findsNothing);
    });

    testWidgets('unreachable renders nothing, not an add button', (
      tester,
    ) async {
      // The state that used to be indistinguishable from "not on your list".
      // Offering to add it here offers an action that is about to fail, which
      // is why the three-way answer exists at all.
      await show(tester, const AniListListResult.unavailable());
      expect(tester.takeException(), isNull);
      expect(find.text('Add to your AniList'), findsNothing);
    });

    testWidgets('not on the list offers to add it', (tester) async {
      await show(tester, const AniListListResult.notOnList());
      expect(tester.takeException(), isNull);
      expect(find.text('Add to your AniList'), findsOneWidget);
      expect(find.text('On your AniList'), findsNothing);
    });

    testWidgets('a row renders status, progress and score', (tester) async {
      await show(
        tester,
        const AniListListResult(
          AniListListLookup.onList,
          AniListListEntry(
            id: 1,
            mediaId: 7,
            status: AniListListStatus.current,
            statusRaw: 'CURRENT',
            progress: 12,
            score: 8.5,
          ),
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
        const AniListListResult(
          AniListListLookup.onList,
          AniListListEntry(
            id: 1,
            mediaId: 7,
            status: AniListListStatus.planning,
            statusRaw: 'PLANNING',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('★'), findsNothing);
      expect(find.textContaining('Planning'), findsOneWidget);
    });

    testWidgets('a whole score drops its pointless decimal', (tester) async {
      await show(
        tester,
        const AniListListResult(
          AniListListLookup.onList,
          AniListListEntry(id: 1, mediaId: 7, progress: 3, score: 8),
        ),
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
