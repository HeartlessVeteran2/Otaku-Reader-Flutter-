// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:html/dom.dart';
import 'package:otaku_reader/source/model/m_element.dart';
import 'package:otaku_reader/source/util/dom_extensions.dart';

class MDocument {
  const MDocument(this._document);

  final Document? _document;

  MElement? get body => MElement(_document?.body);

  MElement? get documentElement => MElement(_document?.documentElement);

  MElement? get head => MElement(_document?.head);

  MElement? get parent => MElement(_document?.parent);

  String? get outerHtml => _document?.outerHtml;

  String? get text => _document?.text?.trim();

  List<MElement>? get children =>
      _document?.children.map((e) => MElement(e)).toList();

  List<MElement>? select(String selector) {
    return _document?.select(selector)?.map((e) => MElement(e)).toList();
  }

  String? xpathFirst(String xpath) {
    return _document?.xpathFirst(xpath);
  }

  List<String> xpath(String xpath) {
    return _document?.xpath(xpath) ?? [];
  }

  List<MElement>? getElementsByClassName(String classNames) {
    return _document
        ?.getElementsByClassName(classNames)
        .map((e) => MElement(e))
        .toList();
  }

  List<MElement>? getElementsByTagName(String localNames) {
    return _document
        ?.getElementsByTagName(localNames)
        .map((e) => MElement(e))
        .toList();
  }

  MElement? getElementById(String id) {
    return MElement(_document?.getElementById(id));
  }

  MElement? selectFirst(String selector) {
    return MElement(_document?.selectFirst(selector));
  }

  String? attr(String attr) {
    return _document?.attr(attr)?.trim();
  }

  bool hasAttr(String attr) {
    return _document?.hasAtr(attr) ?? false;
  }
}
