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
import 'package:html/dom.dart';
import 'package:otaku_reader/source/model/m_document.dart';

class MDocumentBridge {
  final documentBridgedClass = BridgedClass(
    nativeType: MDocument,
    name: 'MDocument',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        return MDocument(positionalArgs[0] as Document);
      },
    },
    getters: {
      'body': (visitor, target) => (target as MDocument).body,
      'documentElement': (visitor, target) =>
          (target as MDocument).documentElement,
      'head': (visitor, target) => (target as MDocument).head,
      'parent': (visitor, target) => (target as MDocument).parent,
      'outerHtml': (visitor, target) => (target as MDocument).outerHtml,
      'text': (visitor, target) => (target as MDocument).text,
      'children': (visitor, target) => (target as MDocument).children,
    },
    methods: {
      'select': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).select(positionalArgs[0] as String),
      'selectFirst': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).selectFirst(positionalArgs[0] as String),
      'getElementsByClassName': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).getElementsByClassName(
            positionalArgs[0] as String,
          ),
      'getElementsByTagName': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).getElementsByTagName(
            positionalArgs[0] as String,
          ),
      'getElementById': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).getElementById(positionalArgs[0] as String),
      'attr': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).attr(positionalArgs[0] as String),
      'hasAttr': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).hasAttr(positionalArgs[0] as String),
      'xpath': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).xpath(positionalArgs[0] as String),
      'xpathFirst': (visitor, target, positionalArgs, namedArgs) =>
          (target as MDocument).xpathFirst(positionalArgs[0] as String),
    },
  );

  void registerBridgedClasses(D4rt interpreter) {
    interpreter.registerBridgedClass(documentBridgedClass, kBridgeLibraryUri);
  }
}
