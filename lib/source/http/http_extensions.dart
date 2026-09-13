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
