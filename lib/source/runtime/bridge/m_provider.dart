// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:otaku_reader/source/runtime/bridge/bridge_library.dart';

import 'package:d4rt/d4rt.dart' hide Logger;
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_bridge.dart';
import 'package:otaku_reader/source/model/m_provider.dart';
import 'package:otaku_reader/source/preference/source_preference_resolver.dart';
import 'package:otaku_reader/core/utils/string_extensions.dart';
import 'package:otaku_reader/source/util/log.dart';

class MProviderBridged {
  final mProviderBridged = BridgedClass(
    nativeType: MProvider,
    name: 'MProvider',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        return MProvider;
      },
    },
    getters: {
      'supportsLatest': (visitor, target) =>
          (target as MProvider).supportsLatest,
      'baseUrl': (visitor, target) => (target as MProvider).baseUrl,
      'headers': (visitor, target) => (target as MProvider).headers,
    },
    methods: {
      'getLatestUpdates': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getLatestUpdates(positionalArgs[0] as int),
      'getPopular': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getPopular(positionalArgs[0] as int),
      'getVideoList': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getVideoList(positionalArgs[0] as String),
      'search': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).search(
            positionalArgs[0] as String,
            positionalArgs[1] as int,
            positionalArgs[2] as FilterList,
          ),
      'getDetail': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getDetail(positionalArgs[0] as String),
      'getPageList': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getPageList(positionalArgs[0] as String),
      'cleanHtmlContent': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).cleanHtmlContent(positionalArgs[0] as String),
      'getHtmlContent': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getHtmlContent(
            positionalArgs[0] as String,
            positionalArgs[1] as String,
          ),
      'getFilterList': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getFilterList(),
      'getSourcePreferences': (visitor, target, positionalArgs, namedArgs) =>
          (target as MProvider).getSourcePreferences(),
    },
  );

  void registerBridgedClasses(D4rt interpreter) {
    interpreter.registerBridgedClass(mProviderBridged, kBridgeLibraryUri);
    interpreter.registertopLevelFunction(
      'getPreferenceValue',
      (visitor, positionalArgs, namedArgs, _) => SourcePreferenceResolver.value(
        positionalArgs[0] as int,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'getPrefStringValue',
      (visitor, positionalArgs, namedArgs, _) =>
          SourcePreferenceResolver.stringValue(
            positionalArgs[0] as int,
            positionalArgs[1] as String,
            positionalArgs[2] as String,
          ),
    );
    interpreter.registertopLevelFunction(
      'cryptoHandler',
      (visitor, positionalArgs, namedArgs, _) => MBridge.cryptoHandler(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
        positionalArgs[2] as String,
        positionalArgs[3] as bool,
      ),
    );
    interpreter.registertopLevelFunction(
      'encryptAESCryptoJS',
      (visitor, positionalArgs, namedArgs, _) => MBridge.encryptAESCryptoJS(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'decryptAESCryptoJS',
      (visitor, positionalArgs, namedArgs, _) => MBridge.decryptAESCryptoJS(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'decryptAESGCM',
      (visitor, positionalArgs, namedArgs, _) => MBridge.decryptAESGCM(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
        positionalArgs[2] as String,
        // tagHex is optional (empty when the tag is already appended); coerce a
        // null/missing arg to "" so the call can't throw before the try/catch.
        positionalArgs[3] as String? ?? '',
      ),
    );
    interpreter.registertopLevelFunction(
      'deobfuscateJsPassword',
      (visitor, positionalArgs, namedArgs, _) =>
          MBridge.deobfuscateJsPassword(positionalArgs[0] as String),
    );
    interpreter.registertopLevelFunction(
      'substringAfter',
      (visitor, positionalArgs, namedArgs, _) => MBridge.substringAfter(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'substringBefore',
      (visitor, positionalArgs, namedArgs, _) => MBridge.substringBefore(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'substringBeforeLast',
      (visitor, positionalArgs, namedArgs, _) => MBridge.substringBeforeLast(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'substringAfterLast',
      (visitor, positionalArgs, namedArgs, _) => MBridge.substringAfterLast(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'getMapValue',
      (visitor, positionalArgs, namedArgs, _) => MBridge.getMapValue(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
        namedArgs.get<bool?>('encode') ?? false,
      ),
    );
    interpreter.registertopLevelFunction(
      'parseStatus',
      (visitor, positionalArgs, namedArgs, _) => MBridge.parseStatus(
        positionalArgs[0] as String,
        positionalArgs[1] as List,
      ),
    );
    interpreter.registertopLevelFunction(
      'parseDates',
      (visitor, positionalArgs, namedArgs, _) => MBridge.parseDates(
        positionalArgs[0] as List,
        positionalArgs[1] as String,
        positionalArgs[2] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'xpath',
      (visitor, positionalArgs, namedArgs, _) => MBridge.xpath(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
      ),
    );
    interpreter.registertopLevelFunction(
      'unpackJs',
      (visitor, positionalArgs, namedArgs, _) =>
          MBridge.unpackJs(positionalArgs[0] as String),
    );
    interpreter.registertopLevelFunction(
      'unpackJsAndCombine',
      (visitor, positionalArgs, namedArgs, _) =>
          MBridge.unpackJsAndCombine(positionalArgs[0] as String),
    );
    interpreter.registertopLevelFunction(
      'evalJs',
      (visitor, positionalArgs, namedArgs, _) => throw UnsupportedError(
        'evalJs is unavailable: the JavaScript engine is not wired up yet.',
      ),
    );
    interpreter.registertopLevelFunction(
      'evalJsSync',
      (visitor, positionalArgs, namedArgs, _) => throw UnsupportedError(
        'evalJsSync is unavailable: the JavaScript engine is not wired up yet.',
      ),
    );
    interpreter.registertopLevelFunction(
      'regExp',
      (visitor, positionalArgs, namedArgs, _) => MBridge.regExp(
        positionalArgs[0] as String,
        positionalArgs[1] as String,
        positionalArgs[2] as String,
        positionalArgs[3] as int,
        positionalArgs[4] as int,
      ),
    );
    interpreter.registertopLevelFunction(
      'sortMapList',
      (visitor, positionalArgs, namedArgs, _) => MBridge.sortMapList(
        positionalArgs[0] as List,
        positionalArgs[1] as String,
        positionalArgs[2] as int,
      ),
    );
    interpreter.registertopLevelFunction(
      'parseHtml',
      (visitor, positionalArgs, namedArgs, _) =>
          MBridge.parsHtml(positionalArgs[0] as String),
    );
    interpreter.registertopLevelFunction(
      'getUrlWithoutDomain',
      (visitor, positionalArgs, namedArgs, _) =>
          (positionalArgs[0] as String).getUrlWithoutDomain,
    );
    interpreter.registertopLevelFunction(
      'evaluateJavascriptViaWebview',
      (visitor, positionalArgs, namedArgs, _) async => false,
    );
    interpreter.registertopLevelFunction('print', (
      visitor,
      positionalArgs,
      namedArgs,
      _,
    ) {
      Log.info('${positionalArgs[0]}');
      return null;
    });
  }
}
