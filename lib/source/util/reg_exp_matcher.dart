// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

String regHrefMatcher(String input) {
  RegExp exp = RegExp(r'href="([^"]+)"');
  Iterable<Match> matches = exp.allMatches(input);
  if (matches.isEmpty) return '';
  return matches.first.group(1) ?? '';
}

String regDataSrcMatcher(String input) {
  RegExp exp = RegExp(r'data-src="([^"]+)"');
  Iterable<Match> matches = exp.allMatches(input);
  if (matches.isEmpty) return '';
  return matches.first.group(1) ?? '';
}

String regSrcMatcher(String input) {
  RegExp exp = RegExp(r'src="([^"]+)"');
  Iterable<Match> matches = exp.allMatches(input);
  if (matches.isEmpty) return '';
  return matches.first.group(1) ?? '';
}

String regImgMatcher(String input) {
  RegExp exp = RegExp(r'img="([^"]+)"');
  Iterable<Match> matches = exp.allMatches(input);
  if (matches.isEmpty) return '';
  return matches.first.group(1) ?? '';
}

String regCustomMatcher(String input, String source, int group) {
  try {
    RegExp exp = RegExp(source);
    Iterable<Match> matches = exp.allMatches(input);
    String? firstMatch = matches.first.group(group);
    return firstMatch!;
  } catch (_) {
    return input;
  }
}

String padIndex(int index) {
  return (index + 1).toString().padLeft(3, '0');
}
