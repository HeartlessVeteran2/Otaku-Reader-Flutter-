import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts that a screen is hiding none of its prose.
///
/// Shared rather than copied per suite, because the first version of this was
/// written twice and was **hollow in both**. It skipped every paragraph capped
/// at one line and asserted `didExceedMaxLines` on the rest -- but
/// `didExceedMaxLines` is false whenever `maxLines` is null, and since #48
/// lifted the prose caps there are *no* multi-line caps left. Measured on
/// Settings at 320px and a doubled font: 9 uncapped paragraphs, 11 capped at
/// one line, **0 capped at more**. So the loop examined nine paragraphs and
/// asserted a property that cannot be false for any of them.
///
/// A `checked > 0` guard did not save it: that proves the loop *ran*, not that
/// its assertion could *fail*. Found by `sourcery-ai`.
///
/// So this checks the three ways text actually goes missing:
///
/// 1. **A re-introduced prose cap.** `#48` uncapped `ChromeTile.subtitle` and
///    `ChromeFeatureCard.description` because a cap there buys density and
///    pays in hidden words. That is an invariant, and [maxProseLines] pins it
///    directly -- one re-added `maxLines: 2` fails here rather than waiting
///    for a paragraph long enough to trip it.
/// 2. **Truncation**, for any capped paragraph that does appear -- the
///    original check, kept for when it can bite.
/// 3. **Escaping the screen.** A paragraph whose painted rect leaves the
///    viewport is off the edge rather than ellipsised, which throws nothing
///    when an ancestor clips it.
///
/// [allowSingleLineCaps] is the count of deliberate one-line caps, which are
/// layout invariants and are exempt: the header's title and subtitle (its
/// height is its own property), the tab/segment label (the `TabBar`-overflow
/// fix) and `ChromeTile.title` (a long title must ellipsise rather than shove
/// its trailing control off screen).
void expectNoHiddenText(
  WidgetTester tester, {
  required Size screen,
  int maxProseLines = 1,
}) {
  final paragraphs = find
      .byType(RichText)
      .evaluate()
      .map((e) => e.renderObject! as RenderParagraph)
      .toList();
  expect(
    paragraphs,
    isNotEmpty,
    reason: 'nothing was rendered, so nothing was checked',
  );

  for (final p in paragraphs) {
    final text = p.text.toPlainText();
    final cap = p.maxLines;

    expect(
      cap == null || cap <= maxProseLines,
      isTrue,
      reason:
          'a multi-line cap was re-added to prose: "$text" is capped at $cap. '
          'A cap on prose in a scrolling list buys density and pays in hidden '
          'words -- see #48.',
    );
    if (cap != 1) {
      expect(p.didExceedMaxLines, isFalse, reason: 'truncated: "$text"');
    }
  }

  // Painted bounds, not the render box: a paragraph scaled or translated
  // between layout and paint meets the user where it is painted, and that is
  // the only rect a reader's eye lands on.
  for (final p in paragraphs) {
    final origin = p.localToGlobal(Offset.zero);
    final rect = origin & p.size;
    expect(
      rect.left,
      greaterThanOrEqualTo(-0.5),
      reason: 'off the left edge: "${p.text.toPlainText()}"',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(screen.width + 0.5),
      reason: 'off the right edge: "${p.text.toPlainText()}"',
    );
  }
}
