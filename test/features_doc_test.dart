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

  test('the honoured-key count is the one the code actually has', () {
    // Derived, never restated. This sentence was hand-written wrong three
    // times in two days -- "six" display keys listed against eight names,
    // "four" `tapZones*` against five, and a total that inherited both. A
    // number a human recounts each time is a number that drifts, and this file
    // is the one whose entire job is not overstating.
    //
    // "Honoured" means *something outside `keys.dart` names the member*. That
    // is deliberately generous: a key written by a Settings row and read by
    // nothing still counts here, because this assertion is about the sentence
    // being arithmetically true, not about the feature being wired. The guard
    // against a dead control is a rendered test in the feature's own suite --
    // see the display group's reader tests.
    final keysFile = File('lib/core/database/data_keys/keys.dart')
        .readAsStringSync();
    final block = RegExp(
      r'enum ReaderKeys\s*\{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(keysFile);
    expect(block, isNotNull, reason: 'ReaderKeys enum not found');

    // Comment lines are stripped **before** the split, not filtered after it.
    // Filtering after is what stood here, and it silently dropped every member
    // carrying a doc comment: the chunk between two commas then begins with
    // `///`, so `startsWith('//')` threw the member away along with its
    // documentation. A doc comment containing a comma fragmented it further.
    // It was correct only for as long as no member in this enum was
    // documented, and the first three that were took the count from 23 to 20
    // without failing anything — a guard against a drifting number, drifting.
    final body = block!
        .group(1)!
        .split('\n')
        .map((l) => l.trim())
        .where((l) => !l.startsWith('//'))
        .join('\n');

    final members = body
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();

    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('data_keys/keys.dart'),
        )
        .map((f) => f.readAsStringSync())
        .toList();

    final honoured = members
        .where(
          (m) =>
              sources.any((src) => RegExp('ReaderKeys\\.$m\\b').hasMatch(src)),
        )
        .length;

    final claim = RegExp(r'\*\*(\d+) honoured of (\d+)\*\*').firstMatch(doc);
    expect(claim, isNotNull, reason: 'the honoured-key sentence is missing');
    expect(
      int.parse(claim!.group(1)!),
      honoured,
      reason:
          'FEATURES.md claims ${claim.group(1)} honoured; the code has '
          '$honoured',
    );
    expect(
      int.parse(claim.group(2)!),
      members.length,
      reason:
          'FEATURES.md claims ${claim.group(2)} declared; ReaderKeys has '
          '${members.length}',
    );
  });
}
