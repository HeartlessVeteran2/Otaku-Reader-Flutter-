// Derived from AnymeX (https://github.com/RyanYuuki/AnymeX),
// MIT License, Copyright (c) 2024 Ryan _.
// See NOTICE and licenses/AnymeX-MIT.txt for the permission notice that
// licence requires to travel with these portions.

import 'package:flutter/material.dart';

/// The page counter that stays on screen once the reader's chrome is hidden.
///
/// Ported from AnymeX's `_buildPageInfo`
/// (`lib/screens/manga/widgets/reader/top_controls.dart:196`) — the same
/// `AnimatedOpacity`, the same `surfaceContainer` pill at radius 12 behind an
/// `onSurface`-at-15% hairline.
///
/// One thing is changed on the way in. AnymeX fades on
/// `showPageIndicator || showControls`, because its bottom controls carry a
/// slider rather than a number. This reader's chrome already renders
/// `'n / total'` in its bottom bar, so that rule would put two counters on
/// screen at once; the caller passes [visible] false while the chrome is up.
///
/// It stays mounted and fades rather than being built conditionally, so the
/// 300ms is a fade rather than a pop — and so a test can find it and ask
/// whether it is actually on screen, which a conditional subtree cannot
/// answer.
class ReaderPageIndicator extends StatelessWidget {
  const ReaderPageIndicator({
    super.key,
    required this.page,
    required this.total,
    required this.visible,
  });

  /// Zero-based, as the controller holds it. Rendered one-based.
  final int page;
  final int total;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      // Never takes a tap, visible or not. It floats over the middle-top of
      // the page, and the reader's one gesture is tap-to-toggle-the-chrome --
      // so a pill that swallowed the tap would be a dead spot the user meets
      // exactly where the number they are watching sits, and a faded-out one
      // would be a dead spot with nothing drawn in it at all. It is a readout,
      // not a control.
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.onSurface.withValues(alpha: 0.15)),
          ),
          child: Text(
            '${page + 1} / $total',
            // Uncapped on purpose. The string is two numbers and a slash, its
            // row has the whole screen width to sit in, and a cap here could
            // only ever hide a digit at a large system font — which is the
            // defect this project already shipped once, where an ellipsis
            // overflow throws nothing and `takeException()` is blind to it.
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
