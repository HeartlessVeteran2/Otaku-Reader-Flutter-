import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `FEATURES.md` is the parity contract, so it has to be internally consistent.
///
/// This exists because the commit that rebuilt that file shipped **four**
/// defects at once: two items listed as both shipped and not shipped
/// (`NSFW gate`, and History's swipe-to-delete/resume), and two ticks that
/// were simply false — an "in-chapter download button" the reader does not
/// have, and multi-select on Updates, which has no selection state at all.
///
/// Three were caught by a review bot and one by an ad-hoc script. A contract
/// that contradicts itself is worse than a stale one, because a stale file is
/// obviously untrustworthy and a contradictory one is only obviously wrong on
/// the line you happen to read.
void main() {
  late final String doc = File('FEATURES.md').readAsStringSync();

  /// `[x] thing`, `[~] thing`, `[ ] thing`, up to the next `·` or newline.
  final item = RegExp(r'\[([x~ ])\]\s*([^·\n|]{3,60})');

  /// The `##` heading an offset falls under.
  String sectionAt(int offset) {
    final heads = RegExp(
      r'^##+ (.+)$',
      multiLine: true,
    ).allMatches(doc.substring(0, offset));
    return heads.isEmpty ? '(preamble)' : heads.last.group(1)!.trim();
  }

  String normalise(String label) => label
      .trim()
      .replaceAll(RegExp(r'\s*\(.*'), '')
      .replaceAll('*', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  test('no item is claimed in two states within one section', () {
    // Scoped by section on purpose. "multi-select" is a genuinely different
    // item under Details than under Downloads — the chapter list has it and
    // the updates list does not — so a global key reports a contradiction
    // that is not one. The first version of this check did exactly that.
    final seen = <String, Set<String>>{};
    for (final m in item.allMatches(doc)) {
      final label = normalise(m.group(2)!);
      if (label.length <= 3) continue;
      seen
          .putIfAbsent('${sectionAt(m.start)} :: $label', () => <String>{})
          .add(m.group(1)!);
    }

    final contradictory = seen.entries.where((e) => e.value.length > 1);
    expect(
      contradictory.map((e) => e.key),
      isEmpty,
      reason: 'each is both ticked and unticked in the same section',
    );
  });

  test('every partial names its gap', () {
    // `[~]` means "partly, with the gap named" — the file says so in its own
    // header. A bare `[~]` is the least useful mark available: it says
    // something is incomplete without saying what is missing, which is the
    // one question the contract exists to answer.
    final bare = <String>[];
    for (final m in RegExp(r'\[~\]\s*([^·\n|]+)').allMatches(doc)) {
      final text = m.group(1)!;
      // The header's own legend explains the convention; it is not an entry.
      if (text.contains('= partly')) continue;
      final namesGap = RegExp(
        r'—|--|\bonly\b|\bno\b|\bnot\b|\bof \d+\b|\bdoes not\b',
      ).hasMatch(text);
      if (!namesGap) bare.add(text.trim());
    }
    expect(bare, isEmpty, reason: 'partial entries with no gap named');
  });

  test('the decisions table still records every skip', () {
    // The standing rule is that nothing is deferred without a line here
    // saying so. If the decisions table loses a row, that rule has quietly
    // stopped being enforced.
    for (final decision in const [
      'anime/novel-only',
      'comments',
      'MangaUpdates',
      'Kotatsu',
    ]) {
      expect(
        doc.toLowerCase(),
        contains(decision.toLowerCase()),
        reason: 'the $decision decision is no longer recorded',
      );
    }
  });
}
