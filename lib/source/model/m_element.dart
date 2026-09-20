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
import 'package:otaku_reader/source/util/dom_extensions.dart';

class MElement {
  MElement(this._element);

  final Element? _element;

  String? get outerHtml => _element?.outerHtml;

  String? get innerHtml => _element?.innerHtml;

  String? get text => _element?.text.trim();

  String? get className => _element?.className;

  String? get localName => _element?.localName;

  String? get namespaceUri => _element?.namespaceUri;

  String? get getSrc => _element?.getSrc;

  String? get getImg => _element?.getImg;

  String? get getHref => _element?.getHref;

  String? get getDataSrc => _element?.getDataSrc;

  List<MElement>? get children =>
      _element?.children.map((e) => MElement(e)).toList();

  MElement? get parent => MElement(_element?.parent);

  MElement? get nextElementSibling => MElement(_element?.nextElementSibling);

  MElement? get previousElementSibling =>
      MElement(_element?.previousElementSibling);

  String? xpathFirst(String xpath) {
    return _element?.outerHtml == null ? null : _element?.xpathFirst(xpath);
  }

  List<String>? xpath(String xpath) {
    return _element?.outerHtml == null ? null : _element?.xpath(xpath);
  }

  List<MElement>? getElementsByClassName(String classNames) {
    return _element
        ?.getElementsByClassName(classNames)
        .map((e) => MElement(e))
        .toList();
  }

  List<MElement>? getElementsByTagName(String localNames) {
    return _element
        ?.getElementsByTagName(localNames)
        .map((e) => MElement(e))
        .toList();
  }

  List<MElement>? select(String selector) {
    return _element?.select(selector)?.map((e) => MElement(e)).toList();
  }

  MElement? selectFirst(String selector) {
    return MElement(_element?.selectFirst(selector));
  }

  String? attr(String attribute) {
    return _element?.attr(attribute);
  }

  bool hasAttr(String attr) {
    return _element?.hasAtr(attr) ?? false;
  }
}
