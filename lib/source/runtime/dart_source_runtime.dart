// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:d4rt/d4rt.dart';

import 'package:otaku_reader/source/http/http_extensions.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/preference/source_preference_resolver.dart';
import 'package:otaku_reader/source/runtime/bridge/bridge_registry.dart';
import 'package:otaku_reader/source/source_methods.dart';
import 'package:otaku_reader/source/util/log.dart';

/// Runs a Mangayomi **Dart** source, unmodified, through the d4rt interpreter.
///
/// This is the backend that matters: of the 363 entries in the Mangayomi manga
/// index, 249 are Dart and they resolve to ~245 distinct sites (seven
/// multi-site template scripts, `madara.dart` alone driving 151). Kotlin cannot
/// interpret them, which is the whole reason this app is written in Dart.
///
/// Extensions run **as published**. If a real source fails here, the fix
/// belongs in this runtime or in the bridge, never in the extension.
class DartSourceRuntime implements SourceMethods {
  DartSourceRuntime(this.source) {
    final code = source.sourceCode;
    if (code == null || code.isEmpty) {
      throw StateError('Source ${source.name} has no code; install it first.');
    }

    _interpreter = D4rt();

    // The bridge must be registered *before* the script is evaluated. An
    // extension declares `class X extends MProvider`, and an `extends` clause
    // resolves at class-definition time -- so a missing MProvider fails the
    // entire script rather than one method. The Kotlin app shipped a JS backend
    // for months where MProvider was never defined anywhere, and every source
    // failed at evaluation with nothing pointing at the cause.
    BridgeRegistry.register(_interpreter!);

    // Normalises the two spellings extensions use for the client. The bridge's
    // `Client` constructor accepts both the no-arg and the source-taking form,
    // so this only removes a difference; it is kept because upstream applies it
    // and some published sources are written against the other spelling.
    _interpreter!.execute(
      source: code.replaceAll('Client(source)', 'Client()'),
      positionalArgs: [source.toMSource()],
    );

    // Lets `getPreferenceValue` inside the script reach this source's declared
    // defaults. Registered by id because the bridge only receives an id.
    SourcePreferenceResolver.register(source.sourceId, getSourcePreferences);
  }

  @override
  final Source source;

  D4rt? _interpreter;

  D4rt get _vm {
    final vm = _interpreter;
    if (vm == null) {
      throw StateError('Source ${source.name} has been disposed.');
    }
    return vm;
  }

  @override
  void dispose() {
    SourcePreferenceResolver.unregister(source.sourceId);
    _interpreter = null;
  }

  /// Headers the source wants on its own requests.
  ///
  /// Two spellings exist in the wild (`headers` as a getter, `getHeader(url)`
  /// as a method) and neither is guaranteed, so both are tried and an empty map
  /// is the floor — no headers is a valid answer, a thrown error is not.
  @override
  Map<String, String> getHeaders() {
    try {
      return (_vm.invoke('headers', []) as Map).cast<String, String>();
    } catch (_) {
      try {
        return (_vm.invoke('getHeader', [source.baseUrl ?? '']) as Map)
            .cast<String, String>();
      } catch (_) {
        return const {};
      }
    }
  }

  /// The base URL in effect, which is not necessarily the one on the record: a
  /// source commonly overrides it from a user-set mirror preference.
  @override
  String get sourceBaseUrl {
    try {
      final baseUrl = _vm.invoke('baseUrl', []) as String?;
      if (baseUrl != null && baseUrl.isNotEmpty) return baseUrl;
    } catch (_) {
      // Older sources expose no baseUrl getter at all.
    }
    return source.baseUrl ?? '';
  }

  /// Defaults to true: a source that does not say is far more likely to support
  /// latest than not, and a wrong false hides a working tab for good.
  @override
  bool get supportsLatest {
    try {
      return _vm.invoke('supportsLatest', []) as bool? ?? true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<MPages> getPopular(int page) async =>
      await _vm.invoke('getPopular', [page]) as MPages;

  @override
  Future<MPages> getLatestUpdates(int page) async =>
      await _vm.invoke('getLatestUpdates', [page]) as MPages;

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async =>
      await _vm.invoke('search', [query, page, filterList]) as MPages;

  @override
  Future<MManga> getDetail(String url) async =>
      await _vm.invoke('getDetail', [_absolute(url)]) as MManga;

  /// Page lists come back in two shapes: a bare URL string, or a map carrying
  /// per-page headers. The headers matter — hotlink-protected CDNs 403 without
  /// the Referer the source recorded here — so the map form must not be
  /// flattened to its url.
  @override
  Future<List<PageUrl>> getPageList(String url) async {
    final result = await _vm.invoke('getPageList', [_absolute(url)]) as List;
    return result.map((e) {
      if (e is String) return PageUrl(e.trim());
      return PageUrl.fromJson((e as Map).toMapStringDynamic!);
    }).toList();
  }

  @override
  FilterList getFilterList() {
    List<dynamic> list = const [];
    try {
      list = _vm.invoke('getFilterList', []) as List;
    } catch (e, st) {
      // A source with no filters is ordinary; an empty list renders as "no
      // filters" rather than failing the browse screen.
      Log.error(e, st);
    }
    return FilterList(_unwrap(list));
  }

  @override
  List<SourcePreference> getSourcePreferences() {
    try {
      return (_vm.invoke('getSourcePreferences', []) as List).cast();
    } catch (_) {
      return const [];
    }
  }

  /// Resolves a source-emitted link against the source's base URL.
  ///
  /// Sources emit links with the domain stripped (`getUrlWithoutDomain` is part
  /// of the bridge for exactly this), then their own `getDetail` hands the value
  /// straight to `Uri.parse` and expects an absolute URL. Whether a given link
  /// comes back absolute or relative varies per site, so resolving here -- once,
  /// where every caller passes through -- is the only place it can be done
  /// reliably. Zinmanga fails without it ("No host specified in URI
  /// /manga/..."), while MangaRead.org happens to emit absolute links and works
  /// either way; that difference is why this cannot be left to call sites.
  ///
  /// An already-absolute URL is returned untouched.
  String _absolute(String url) {
    if (url.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme && parsed.hasAuthority) return url;

    final base = sourceBaseUrl;
    if (base.isEmpty) return url;
    try {
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      // A base URL that will not parse is the source's problem, but failing the
      // whole request over it is worse than handing the script what it gave us.
      return url;
    }
  }

  /// Unwraps interpreter values into native ones, recursively.
  ///
  /// Nested filters arrive as [BridgedInstance] wrappers around the native
  /// object, and the three container filters hold *more* filters — so
  /// unwrapping only the top level leaves wrappers inside `values`/`state`
  /// that the UI cannot render.
  List<dynamic> _unwrap(List<dynamic> filters) {
    return filters.map((e) {
      if (e is BridgedInstance) e = e.nativeObject;
      if (e is SelectFilter) {
        return SelectFilter(
          e.type,
          e.name,
          e.state,
          _unwrap(e.values),
          e.typeName,
        );
      }
      if (e is SortFilter) {
        return SortFilter(
          e.type,
          e.name,
          e.state,
          _unwrap(e.values),
          e.typeName,
        );
      }
      if (e is GroupFilter) {
        return GroupFilter(e.type, e.name, _unwrap(e.state), e.typeName);
      }
      return e;
    }).toList();
  }
}
