import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/features/settings/screens/settings_screen.dart';

/// The label beside each multiplier slider has to say the number the slider
/// is actually on.
///
/// It did not. `toStringAsFixed(1)` against the roundness slider's 0.25 step
/// printed "0.3x" for 0.25 and "2.8x" for 2.75 — six of thirteen stops
/// reporting a value the app was not set to, and two neighbouring stops that
/// a reader could not tell apart. Found by `codeant-ai` on #54.
///
/// So the guard is not "0.25 formats as 0.25x". It walks **every stop of
/// every slider** and parses the label back, because the defect was a step
/// the formatter could not express, and only enumerating the steps finds
/// that. A test pinned to whatever value happened to be on screen would have
/// passed the whole time.
void main() {
  /// Mirrors the three rows on the Settings screen. If a row's `divisions` or
  /// bounds change there and not here, the pair disagree and this stops being
  /// about the real sliders -- which is why the bounds come from
  /// `ChromeMetrics` rather than being retyped.
  const sliders = <String, ({double max, int divisions})>{
    'Corner roundness': (max: ChromeMetrics.maxRadiusScale, divisions: 12),
    'Glow': (max: ChromeMetrics.maxGlowScale, divisions: 10),
    'Header blur': (max: ChromeMetrics.maxBlurScale, divisions: 10),
  };

  group('every stop a slider can land on is written exactly', () {
    for (final entry in sliders.entries) {
      test(entry.key, () {
        final slider = entry.value;
        for (var i = 0; i <= slider.divisions; i++) {
          // Exactly how Material computes a division's value, so these are
          // the reachable stops rather than a guess at them.
          final value =
              ChromeMetrics.minScale +
              (slider.max - ChromeMetrics.minScale) * i / slider.divisions;
          final label = scaleLabel(value);

          expect(
            label.endsWith('x'),
            isTrue,
            reason: '$label is a multiplier, not a bare number',
          );
          expect(
            double.parse(label.substring(0, label.length - 1)),
            closeTo(value, 1e-9),
            reason: 'stop $i of ${entry.key} is $value and the row says $label',
          );
        }
      });
    }
  });

  test('a whole multiplier keeps one decimal rather than becoming bare', () {
    // "1x" beside "0.25x" reads as a different kind of quantity. The trim
    // stops at one decimal on purpose.
    expect(scaleLabel(1), '1.0x');
    expect(scaleLabel(0), '0.0x');
    expect(scaleLabel(3), '3.0x');
  });
}
