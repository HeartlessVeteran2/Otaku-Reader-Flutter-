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
import 'package:otaku_reader/source/runtime/bridge/bridge_library.dart';
import 'package:otaku_reader/source/model/m_source.dart';

class MSourceBridge {
  final mSourceBridgedClass = BridgedClass(
    nativeType: MSource,
    name: 'MSource',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        return MSource(
          id: namedArgs.get<int?>('id'),
          name: namedArgs.get<String?>('name'),
          baseUrl: namedArgs.get<String?>('baseUrl'),
          lang: namedArgs.get<String?>('lang'),
          isFullData: namedArgs.get<bool?>('isFullData'),
          hasCloudflare: namedArgs.get<bool?>('hasCloudflare'),
          dateFormat: namedArgs.get<String?>('dateFormat'),
          dateFormatLocale: namedArgs.get<String?>('dateFormatLocale'),
          apiUrl: namedArgs.get<String?>('apiUrl'),
          additionalParams: namedArgs.get<String?>('additionalParams'),
          notes: namedArgs.get<String?>('notes'),
        );
      },
    },
    getters: {
      'id': (visitor, target) => (target as MSource).id,
      'name': (visitor, target) => (target as MSource).name,
      'baseUrl': (visitor, target) => (target as MSource).baseUrl,
      'lang': (visitor, target) => (target as MSource).lang,
      'isFullData': (visitor, target) => (target as MSource).isFullData,
      'hasCloudflare': (visitor, target) => (target as MSource).hasCloudflare,
      'dateFormat': (visitor, target) => (target as MSource).dateFormat,
      'dateFormatLocale': (visitor, target) =>
          (target as MSource).dateFormatLocale,
      'apiUrl': (visitor, target) => (target as MSource).apiUrl,
      'additionalParams': (visitor, target) =>
          (target as MSource).additionalParams,
      'notes': (visitor, target) => (target as MSource).notes,
    },
  );
  void registerBridgedClasses(D4rt interpreter) {
    interpreter.registerBridgedClass(mSourceBridgedClass, kBridgeLibraryUri);
  }
}
