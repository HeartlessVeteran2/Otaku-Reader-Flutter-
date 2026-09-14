import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// An in-memory stand-in for the keystore.
///
/// Not a mock of the platform channel: `FlutterSecureStorage` reaches a real
/// Android keystore that a host-VM test has no access to, which is why
/// `AniListAuth` takes one as a parameter at all.
class FakeVault implements FlutterSecureStorage {
  final store = <String, String>{};

  /// When set, every [read] throws it — an unavailable secure element.
  Object? failWith;

  /// When set, every [write] throws it: the keystore is readable but will not
  /// accept new entries. Separate from [failWith] because it produces a
  /// different outcome — a live session that cannot be persisted.
  Object? failWrites;

  /// When set, every [delete] throws it, so a sign-out clears memory and
  /// leaves the stored token behind to resurrect the account.
  Object? failDeletes;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWith != null) throw failWith!;
    return store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites != null) throw failWrites!;
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failDeletes != null) throw failDeletes!;
    store.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// A client that answers one canned body, and records what was sent.
///
/// Hand-rolled rather than `package:http/testing.dart`'s, so the suite does not
/// take a dependency for one callback.
class FakeClient extends http.BaseClient {
  FakeClient(this.body, {this.status = 200, this.sent});

  /// Fails every request the way an offline device does — before any status
  /// code exists. Distinct from a 5xx, and the two must not be conflated:
  /// neither is a reason to delete the user's token.
  factory FakeClient.offline({List<http.Request>? sent}) =>
      _OfflineClient(sent: sent);

  final String body;
  final int status;

  /// When given, every request is appended — the only way to assert that a
  /// call was *not* made.
  final List<http.Request>? sent;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent?.add(
      http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..body = request is http.Request ? request.body : '',
    );
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: const {'content-type': 'application/json'},
    );
  }
}

/// A `Viewer` payload in AniList's own shape.
String viewerBody({
  String format = 'POINT_10_DECIMAL',
  String name = 'Reader',
  String? avatar = 'https://img.test/a.png',
}) => jsonEncode({
  'data': {
    'Viewer': {
      'id': 7,
      'name': name,
      'avatar': avatar == null ? null : {'large': avatar},
      'mediaListOptions': {'scoreFormat': format},
    },
  },
});

class _OfflineClient extends FakeClient {
  _OfflineClient({super.sent}) : super('');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent?.add(http.Request(request.method, request.url));
    throw const SocketException('Network is unreachable');
  }
}

/// AniList's own shape for a refused token: HTTP 400, message in the body.
String invalidTokenBody() => jsonEncode({
  'data': null,
  'errors': [
    {'message': 'Invalid token', 'status': 400},
  ],
});
