import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:otaku_reader/data/anilist/anilist_auth.dart';

import 'helpers/anilist_fakes.dart';

void main() {
  test('a build with no client id cannot sign in, and says so', () {
    // The state of every fresh clone. It has to be distinguishable from
    // "signed out", because the fix is completely different: one is a sign-in
    // button, the other is a setup instruction.
    final auth = AniListAuth(storage: FakeVault(), clientId: '');
    expect(auth.isConfigured, isFalse);
  });

  test('the authorize url asks for a token, not a code', () {
    // `response_type=token` is the implicit grant, which is what makes the pin
    // page show a token the user can paste. `code` would hand back something
    // that needs a second call *and* the client secret, which an app shipping
    // its own binary cannot keep.
    final auth = AniListAuth(storage: FakeVault(), clientId: 'abc');
    expect(auth.authorizeUrl.queryParameters['response_type'], 'token');
    expect(auth.authorizeUrl.queryParameters['client_id'], 'abc');
  });

  test('signing in stores the token only once AniList accepts it', () async {
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );

    expect(await auth.signIn('  good-token  '), isTrue);
    expect(
      vault.store['anilist_access_token'],
      'good-token',
      reason: 'trimmed, because a paste carries whitespace',
    );
    expect(auth.viewer.value?.name, 'Reader');
  });

  test('a rejected token is not stored and leaves the app signed out', () async {
    // The likeliest failure is a truncated paste. Storing it anyway would mean
    // the app believes it is signed in and every later call fails instead.
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(jsonEncode({'errors': <Object>[]})),
    );

    expect(await auth.signIn('bad-token'), isFalse);
    expect(vault.store, isEmpty);
    expect(auth.isSignedIn, isFalse);
    expect(auth.viewer.value, isNull);
  });

  test('a GraphQL error is a failure even when data came back too', () async {
    // The case that actually needs the check, and the one an obvious test
    // misses. A 200 carrying *only* `errors` already fails on the absent
    // `data`, so a test shaped that way passes with the check deleted — it
    // proves nothing. GraphQL's partial-failure shape is a 200 carrying
    // **both**, and there the status code and the payload both look like
    // success.
    //
    // It matters beyond sign-in: `query` is the one authenticated call the
    // rest of AniList goes through, and a mutation that half-failed answers
    // exactly this way. Reporting it as success would tell the user their
    // score saved when it did not.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(
        jsonEncode({
          'data': {
            'Viewer': {
              'id': 7,
              'name': 'Reader',
              'mediaListOptions': {'scoreFormat': 'POINT_10'},
            },
          },
          'errors': [
            {'message': 'Internal server error'},
          ],
        }),
      ),
    );

    expect(await auth.signIn('partial'), isFalse);
    expect(
      auth.viewer.value,
      isNull,
      reason: 'the half-answer is discarded, not shown as an account',
    );
  });

  test('a successful sign-in leaves the screens with an answer', () async {
    // `isReady` is what every screen gates its spinner on. Tying it to
    // `restore` alone makes it mean "startup ran", which is true in the app
    // and false anywhere else — a spinner with nothing behind it.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    expect(auth.isReady.value, isFalse);

    await auth.signIn('t');

    expect(auth.isReady.value, isTrue);
  });

  test('a transport failure is a refusal, not a crash', () async {
    // AniList being down must not throw out of a sign-in tap.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient('<html>502</html>', status: 502),
    );
    expect(await auth.signIn('t'), isFalse);
  });

  test('the score format comes from the account, not a default', () async {
    // AniList stores every score as 0-100 whatever this says. A five-star user
    // shown "8.0" reads as the wrong number rather than the wrong unit, and
    // ten-point-decimal is AniList's own default — so hardcoding it looks
    // right for most users and wrong for the rest.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(format: 'POINT_5')),
    );
    await auth.signIn('t');
    expect(auth.viewer.value?.scoreFormat, ScoreFormat.point5);
  });

  test('an unknown score format falls back rather than throwing', () async {
    // AniList could add one. A tracker adding an enum value must not stop the
    // user signing in.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(format: 'POINT_42')),
    );
    await auth.signIn('t');
    expect(auth.viewer.value?.scoreFormat, ScoreFormat.point10Decimal);
  });

  test('restore reads the stored token and sends it', () async {
    final sent = <http.Request>[];
    final vault = FakeVault()..store['anilist_access_token'] = 'stored';
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody(), sent: sent),
    );

    await auth.restore();

    expect(auth.isSignedIn, isTrue);
    expect(auth.viewer.value?.name, 'Reader');
    expect(auth.isReady.value, isTrue);
    expect(sent.single.headers['Authorization'], 'Bearer stored');
  });

  test('restore with no stored token asks AniList nothing', () async {
    // A first launch. An anonymous `Viewer` query would answer with an error
    // the app has no use for, on every cold start.
    final sent = <http.Request>[];
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(), sent: sent),
    );

    await auth.restore();

    expect(sent, isEmpty);
    expect(auth.isReady.value, isTrue);
    expect(auth.viewer.value, isNull);
  });

  test('an unreadable keystore is signed out, not a crash', () async {
    // A restored backup or a broken secure element. Nothing else in the app
    // depends on this, so the honest answer is "signed out" — the user can
    // sign in again, which they cannot do if the app fails to start.
    final vault = FakeVault()..failWith = Exception('keystore unavailable');
    final auth = AniListAuth(storage: vault, clientId: 'abc');

    await auth.restore();

    expect(auth.isSignedIn, isFalse);
    expect(
      auth.isReady.value,
      isTrue,
      reason: 'ready with an answer, rather than stuck on the spinner',
    );
  });

  test('signing out forgets the token and the account', () async {
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.signIn('t');
    expect(vault.store, isNotEmpty);

    await auth.signOut();

    expect(vault.store, isEmpty);
    expect(auth.isSignedIn, isFalse);
    expect(auth.viewer.value, isNull);
  });

  test('an unauthenticated query is refused before it is sent', () async {
    // Not merely "returns null": a call with no token must not reach AniList
    // at all, because an anonymous request to a mutation would be a confusing
    // failure rather than an obvious one.
    final sent = <http.Request>[];
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(), sent: sent),
    );

    expect(await auth.query('query { Viewer { id } }'), isNull);
    expect(sent, isEmpty);
  });
}
