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
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';

class MPagesBridge {
  final mPageBridgedClass = BridgedClass(
    nativeType: MPages,
    name: 'MPages',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        return MPages(
          list: (positionalArgs[0] as List).map((e) => e as MManga).toList(),
          hasNextPage: positionalArgs[1] as bool,
        );
      },
    },
    getters: {
      'list': (visitor, target) => (target as MPages).list,
      'hasNextPage': (visitor, target) => (target as MPages).hasNextPage,
    },
    setters: {
      'list': (visitor, target, value) =>
          (target as MPages).list = (value as List).cast<MManga>(),
      'hasNextPage': (visitor, target, value) =>
          (target as MPages).hasNextPage = value as bool,
    },
  );
  void registerBridgedClasses(D4rt interpreter) {
    interpreter.registerBridgedClass(mPageBridgedClass, kBridgeLibraryUri);
  }
}
