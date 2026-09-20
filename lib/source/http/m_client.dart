// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import 'package:otaku_reader/source/model/m_source.dart';
import 'package:otaku_reader/source/util/log.dart';

/// The HTTP client every extension request goes through.
///
/// Extensions write `final Client client = Client();` and call `get`/`post` on
/// it, so this must present `package:http`'s surface — the bridge maps
/// `Client` to [InterceptedClient], and [init] is what its constructor calls.
///
/// **One client, not two.** The Kotlin app maintained a separate stack for
/// extension traffic and for page images; only one carried cookies, so a
/// Cloudflare clearance solved in the WebView never reached the other and the
/// bypass silently did nothing for JavaScript sources, page images and OPDS
/// alike. Everything here shares one client and therefore one jar.
class MClient {
  /// A desktop-browser UA by default: a large share of manga hosts answer
  /// anything else with a challenge page or a flat 403. An extension that needs
  /// something specific sets its own header, which wins.
  static const defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static InterceptedClient init({
    MSource? source,
    Map<String, dynamic>? reqcopyWith,
    bool showCloudFlareError = true,
  }) {
    return InterceptedClient.build(
      client: http.Client(),
      interceptors: [
        DefaultHeadersInterceptor(source: source, overrides: reqcopyWith),
      ],
    );
  }

  /// Headers for a page-image request.
  ///
  /// Non-obvious and load-bearing: hotlink-protected CDNs answer a bare GET with
  /// 403, and the fix is `Referer` plus `Origin` derived from the source's base
  /// URL. Any header the source recorded with the page wins, because a source
  /// that bothered to set one knows something this default does not.
  static Map<String, String> pageImageHeaders(
    Map<String, String>? pageHeaders, [
    String? baseUrl,
  ]) {
    final base = baseUrl ?? '';
    final referer = base.isEmpty ? '' : (base.endsWith('/') ? base : '$base/');
    final origin = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return {
      'User-Agent': defaultUserAgent,
      if (referer.isNotEmpty) 'Referer': referer,
      if (origin.isNotEmpty) 'Origin': origin,
      'Accept':
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      ...?pageHeaders,
    };
  }
}

/// Fills in a User-Agent and the source's Referer when the script set neither.
class DefaultHeadersInterceptor implements InterceptorContract {
  DefaultHeadersInterceptor({this.source, this.overrides});

  final MSource? source;
  final Map<String, dynamic>? overrides;

  @override
  Future<bool> shouldInterceptRequest() async => true;

  @override
  Future<bool> shouldInterceptResponse() async => true;

  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    // Header names are case-insensitive on the wire but not in this map, so a
    // script that set 'user-agent' must not be given a second 'User-Agent'.
    final present = request.headers.keys.map((k) => k.toLowerCase()).toSet();

    if (!present.contains('user-agent')) {
      request.headers['User-Agent'] = MClient.defaultUserAgent;
    }
    final base = source?.baseUrl;
    if (!present.contains('referer') && base != null && base.isNotEmpty) {
      request.headers['Referer'] = base.endsWith('/') ? base : '$base/';
    }
    overrides?.forEach((key, value) {
      if (value is String) request.headers[key] = value;
    });
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async {
    // A Cloudflare interstitial is the single most common source failure, and
    // it is indistinguishable from a genuine block without the server header.
    // Surfacing it here means a tap-to-solve WebView can be offered instead of
    // a bare "source not working".
    final server = response.headers['server']?.toLowerCase();
    if ((response.statusCode == 403 || response.statusCode == 503) &&
        (server == 'cloudflare' || server == 'cloudflare-nginx')) {
      Log.info('Cloudflare challenge at ${response.request?.url}');
    }
    return response;
  }
}
