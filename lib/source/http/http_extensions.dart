// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

/// Coercions used when a value crosses the interpreter boundary.
///
/// Interpreted code hands back `Map<dynamic, dynamic>`, because a script has no
/// static types to preserve. These convert at the edge so the rest of the app
/// can rely on the declared types.
extension MapCoercions on Map? {
  Map<String, String>? get toMapStringString =>
      this?.map((k, v) => MapEntry(k.toString(), v.toString()));

  Map<String, dynamic>? get toMapStringDynamic =>
      this?.map((k, v) => MapEntry(k.toString(), v));
}
