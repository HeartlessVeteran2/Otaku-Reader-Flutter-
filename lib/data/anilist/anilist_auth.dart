import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// How a user's AniList score is displayed, read from their own account.
///
/// AniList stores every score as a 0-100 double regardless; this only says how
/// to show it. Hardcoding ten-point decimal — which is AniList's own default —
/// would show a five-star user "8.0" for what their web profile calls four
/// stars, which reads as the app having the wrong number rather than the wrong
/// unit.
enum ScoreFormat {
  point100('POINT_100'),
  point10Decimal('POINT_10_DECIMAL'),
  point10('POINT_10'),
  point5('POINT_5'),
  point3('POINT_3');

  const ScoreFormat(this.wire);

  /// The value AniList's API uses.
  final String wire;

  static ScoreFormat parse(String? value) => ScoreFormat.values.firstWhere(
    (f) => f.wire == value,
    orElse: () => ScoreFormat.point10Decimal,
  );
}

/// The signed-in AniList account.
class AniListViewer {
  const AniListViewer({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.scoreFormat = ScoreFormat.point10Decimal,
  });

  final int id;
  final String name;
  final String? avatarUrl;
  final ScoreFormat scoreFormat;
}

/// What came of offering AniList a token.
///
/// Three outcomes rather than a bool, because "AniList refused this" and "this
/// device could not keep it" need different words in front of the user: one is
/// a re-paste, the other is a session that works now and is gone after a
/// restart. Collapsing them meant a keystore write failure threw out of
/// [AniListAuth.signIn] *after* the viewer was published — signed in, surfaced
/// as an unhandled error, and unexplained.
enum SignInResult {
  /// Accepted and stored.
  ok,

  /// Accepted, but this device could not store it.
  notPersisted,

  /// AniList refused it.
  rejected,
}

/// How one authenticated call ended.
///
/// The distinction between [rejected] and [unreachable] is the whole point:
/// only a refusal may delete the user's stored token. A failure to *ask* —
/// offline, AniList down, a proxy's error page — must keep it, because
/// signing someone out for being on a train is the worse failure and the next
/// launch will simply ask again.
enum _Auth { ok, rejected, unreachable }

/// One authenticated call's result.
class _Response {
  const _Response({this.data, this.rejected = false});

  final Map<String, dynamic>? data;
  final bool rejected;
}

Map<String, dynamic>? _mapOf(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

String? _stringOf(Object? value) => value is String ? value : null;

/// Signs in to AniList and holds the token.
///
/// **The token lives in `flutter_secure_storage`, never in the KV tier.** That
/// table is an ordinary Isar collection: a backup, a debug dump or anything
/// that can read the database file would carry the token off in clear text,
/// and an AniList token can rewrite the user's whole list. AnymeX keeps its
/// auth tokens in its KV table; this is one of the things `CLAUDE.md` says not
/// to copy.
///
/// ## Why PIN, not a redirect
///
/// AniList's implicit grant can redirect to `…/oauth/pin`, which shows the
/// token on screen for the user to paste back. The alternative — a real
/// redirect URI — needs either a WebView to intercept it or an intent filter
/// and deep-link plumbing, which is two more Android plugins and a manifest
/// entry for a flow the user runs approximately once. Pasting a token is
/// slightly clumsier and very much simpler, and it keeps the token out of a
/// WebView this app would then own.
///
/// ## Nothing here throws
///
/// Every entry point returns its failure. The keystore can fail on a device
/// with a broken secure element, AniList can answer anything at all, and
/// [restore] in particular is launched unawaited from `AppBindings` — so an
/// exception escaping it has nobody to catch it and becomes an unhandled
/// async error at startup.
class AniListAuth {
  AniListAuth({
    FlutterSecureStorage? storage,
    http.Client? client,
    String? clientId,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client(),
       clientId = clientId ?? _configuredClientId;

  static const _tokenKey = 'anilist_access_token';
  static const _endpoint = 'https://graphql.anilist.co';

  /// Supplied at build time, because it identifies *this build* of the app to
  /// AniList and is the developer's to register, not something that can be
  /// committed usefully.
  ///
  /// Empty is a first-class state, not a failure: a fresh clone has no client
  /// id and must render a setup instruction rather than a broken sign-in
  /// button. See [isConfigured].
  static const _configuredClientId = String.fromEnvironment(
    'ANILIST_CLIENT_ID',
  );

  final FlutterSecureStorage _storage;
  final http.Client _client;

  /// The AniList application id this build authenticates as.
  final String clientId;

  /// Whether this build can sign in at all.
  ///
  /// False on any build that was not given a client id, which includes every
  /// fresh clone. The UI must say so and explain how to fix it; a sign-in
  /// button that fails on tap is worse than one that is not offered.
  bool get isConfigured => clientId.isNotEmpty;

  /// The signed-in account, or null.
  final viewer = Rxn<AniListViewer>();

  /// True once there is an answer to render, whatever that answer is.
  ///
  /// Distinct from `viewer == null`: "not signed in" and "not looked yet" are
  /// different screens, and conflating them flashes a signed-out state at a
  /// user who is signed in.
  ///
  /// Set by [restore] whatever it finds, **and** by a successful [signIn].
  /// Both establish an answer, and tying it to [restore] alone would make the
  /// flag mean "startup ran" rather than what every screen actually gates on —
  /// a difference invisible in the app, where [restore] always runs first, and
  /// a spinner that never ends anywhere it does not.
  final isReady = false.obs;

  String? _token;

  /// Whether a token is held. Says nothing about whether AniList still accepts
  /// it — only a call that comes back does that, which is why [restore] makes
  /// one before this is trusted.
  bool get isSignedIn => _token != null;

  /// The URL that grants a token, for the user to open.
  ///
  /// `response_type=token` is the implicit grant: AniList shows the token on
  /// its pin page rather than redirecting anywhere this app has to catch.
  ///
  /// **No `redirect_uri`, deliberately.** AniList documents that parameter for
  /// the *authorization code* grant only, where it warns it "must exactly
  /// match the redirect URI you used in your application settings"; the
  /// implicit grant takes `client_id` alone and sends the user "back to the
  /// redirect URI you specified in your application settings"
  /// (docs.anilist.co/guide/auth/implicit vs …/authorization-code). So adding
  /// one cannot help and can only hurt: a build whose registered redirect is
  /// anything but the pin page would fail that exact-match check on a request
  /// that works today. A test asserts the parameter stays absent, because
  /// adding it looks like a fix.
  Uri get authorizeUrl => Uri.https('anilist.co', '/api/v2/oauth/authorize', {
    'client_id': clientId,
    'response_type': 'token',
  });

  /// Reads the stored token and, if there is one, who it belongs to.
  Future<void> restore() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      // A device whose keystore is unavailable — a restored backup, a broken
      // secure element. Treated as signed out rather than fatal: the user can
      // sign in again, and nothing else in the app depends on this.
      _token = null;
    }
    if (_token != null && await _loadViewer() == _Auth.rejected) {
      // Forget a token AniList has **refused**, so a dead one is not carried
      // and retried at every launch for the life of the install.
      //
      // Only a refusal. `loadViewer` also answers "no" for a device with no
      // network and for a malformed reply, and deleting the token there would
      // sign out a user whose token is fine — a far worse outcome than one
      // wasted request, and unrecoverable without the pin flow again.
      await signOut();
    }
    isReady.value = true;
  }

  /// Offers [token] to AniList and, if it is accepted, stores it.
  ///
  /// Nothing is stored until AniList confirms the token, so a mistyped or
  /// truncated paste cannot leave the app believing it is signed in.
  Future<SignInResult> signIn(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return SignInResult.rejected;
    _token = trimmed;
    if (await _loadViewer() != _Auth.ok) {
      _token = null;
      viewer.value = null;
      return SignInResult.rejected;
    }
    isReady.value = true;
    try {
      await _storage.write(key: _tokenKey, value: trimmed);
    } catch (_) {
      // The token is good and the session is live — only persistence failed.
      // Rolling back would report a rejection that did not happen and send
      // the user off to re-paste a token that works.
      return SignInResult.notPersisted;
    }
    return SignInResult.ok;
  }

  /// Forgets the token and the account.
  ///
  /// Returns whether the *stored* token was actually erased. The session ends
  /// either way, but a failed delete means the token outlives it and signs the
  /// user back in at the next launch — so the caller has something to say. A
  /// "signed out" that silently reverses itself is exactly the kind of quiet
  /// lie this project's notes keep recording.
  Future<bool> signOut() async {
    _token = null;
    viewer.value = null;
    try {
      await _storage.delete(key: _tokenKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the signed-in account and publishes it.
  Future<_Auth> _loadViewer() async {
    final response = await _send(_viewerQuery, const {});
    if (response.rejected) {
      viewer.value = null;
      return _Auth.rejected;
    }
    final me = _mapOf(response.data?['Viewer']);
    final id = me?['id'];
    // Every field is *checked*, not cast. A malformed 200 — a captive portal's
    // login page, a proxy error, a shape change — would otherwise throw, and
    // `restore` is unawaited at startup, so that becomes an unhandled async
    // error with no screen to report it on.
    if (me == null || id is! int) {
      viewer.value = null;
      return _Auth.unreachable;
    }
    final name = _stringOf(me['name']);
    viewer.value = AniListViewer(
      id: id,
      name: name == null || name.isEmpty ? 'AniList' : name,
      avatarUrl: _stringOf(_mapOf(me['avatar'])?['large']),
      scoreFormat: ScoreFormat.parse(
        _stringOf(_mapOf(me['mediaListOptions'])?['scoreFormat']),
      ),
    );
    return _Auth.ok;
  }

  /// Runs an **authenticated** GraphQL call. Null on any failure.
  ///
  /// Deliberately swallows the error rather than throwing: every caller here
  /// treats AniList as a disposable upstream, and a tracker that is down must
  /// not take a screen with it.
  Future<Map<String, dynamic>?> query(
    String document, {
    Map<String, dynamic> variables = const {},
  }) async => (await _send(document, variables)).data;

  Future<_Response> _send(
    String document,
    Map<String, dynamic> variables,
  ) async {
    final token = _token;
    // Refused before it is sent. An anonymous request would be a confusing
    // failure rather than an obvious one, and on a mutation a dangerous one.
    if (token == null) return const _Response();

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': document, 'variables': variables}),
      );
    } catch (_) {
      return const _Response();
    }

    Map<String, dynamic>? body;
    try {
      body = _mapOf(jsonDecode(response.body));
    } catch (_) {
      body = null;
    }

    if (_isRefusal(response.statusCode, body)) {
      return const _Response(rejected: true);
    }
    if (response.statusCode != 200 || body == null) return const _Response();
    // GraphQL answers 200 with an `errors` array, so the status code alone is
    // not success. It can carry `data` *and* `errors` together — a partially
    // failed mutation — and reporting that as success would tell the user a
    // score saved when it did not.
    if (body['errors'] != null) return const _Response();
    return _Response(data: _mapOf(body['data']));
  }

  /// Whether AniList refused the *credentials*, as opposed to failing for any
  /// other reason.
  ///
  /// Deliberately narrow, and it errs toward "no": the only thing that turns
  /// on it is deleting the user's stored token, so a false positive signs
  /// someone out over a bad query of ours or a gateway's error page. 401 is
  /// unambiguous. AniList also answers **400** for an expired token — but 400
  /// is equally its answer to a malformed query, which is this app's bug and
  /// not the user's problem, so the status alone cannot decide and the message
  /// has to be read.
  static bool _isRefusal(int status, Map<String, dynamic>? body) {
    if (status == 401) return true;
    if (status != 400) return false;
    final errors = body?['errors'];
    if (errors is! List) return false;
    return errors.any((error) {
      final message = _stringOf(_mapOf(error)?['message'])?.toLowerCase();
      return message != null &&
          (message.contains('invalid token') ||
              message.contains('unauthorized'));
    });
  }

  static const _viewerQuery = '''
query {
  Viewer {
    id
    name
    avatar { large }
    mediaListOptions { scoreFormat }
  }
}
''';
}
