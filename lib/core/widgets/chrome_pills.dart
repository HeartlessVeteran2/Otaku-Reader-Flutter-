// Derived from AnymeX (https://github.com/RyanYuuki/AnymeX),
// MIT License, Copyright (c) 2024 Ryan _.
// See NOTICE and licenses/AnymeX-MIT.txt for the permission notice that
// licence requires to travel with these portions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';

/// One pill in a [ChromePills] row.
class ChromePill {
  const ChromePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Rendered beside the label rather than inside it.
  ///
  /// AnymeX builds the string `'$listName ($itemCount)'` and hands that to one
  /// `Text`, which means the ellipsis eats the number before it eats the name:
  /// a long category reads `Very Long Categ…` with the count gone. Two
  /// children, and only the label is allowed to shorten.
  final int? count;
}

/// A horizontally scrolling row of pills — AnymeX's `AnymeXPills`.
///
/// **This is not [SegmentedTabs], and the difference is the whole reason it
/// exists.** A segmented tab bar gives every tab `1 / total` of the width by
/// construction, which is what makes it un-overflowable and is exactly wrong
/// for a list whose length the user controls: eight categories would each get
/// an eighth of the screen, and every label would be a stub. A scrolling row
/// sizes each pill to its own content instead, and pays for that with a cap
/// (see [maxPillWidthShare]).
///
/// Unselected pills are *connective* — the first and last carry the outer
/// radius and the ones between carry a small inner one, so the row reads as a
/// single strip. The selected pill animates to a full capsule. That morph is
/// AnymeX's, and it is what tells the eye which pill is live without relying
/// on colour alone.
class ChromePills extends StatelessWidget {
  const ChromePills({
    super.key,
    required this.pills,
    this.padding = const EdgeInsets.symmetric(horizontal: Chrome.gutter),
    this.maxPillWidthShare = 0.6,
  });

  final List<ChromePill> pills;
  final EdgeInsets padding;

  /// The widest a single pill may be, as a share of the viewport.
  ///
  /// A horizontal scroll view hands its child **unbounded** width, so a long
  /// name produces no overflow stripe and no exception — it produces one pill
  /// wider than the screen that every other pill has to be scrolled past. The
  /// cap is a share rather than a constant because a port changes the
  /// composition a constant was chosen for; that lesson is already in
  /// `CLAUDE.md`, from the tap-zone preview that was copied at 9/16 and pushed
  /// every slider below the fold.
  final double maxPillWidthShare;

  @override
  Widget build(BuildContext context) {
    if (pills.isEmpty) return const SizedBox.shrink();

    // A non-positive viewport removes the cap instead of scaling it to zero.
    // `MediaQuery` reads zero under a hand-built `MediaQueryData`, and a
    // `maxWidth: 0` does not shrink a pill, it erases it — the same rule as
    // `ChromeCard` dropping a zero-sigma `BackdropFilter` rather than
    // compositing one.
    final viewport = MediaQuery.sizeOf(context).width;
    final maxWidth = viewport > 0
        ? viewport * maxPillWidthShare
        : double.infinity;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, pill) in pills.indexed) ...[
            if (index > 0) const SizedBox(width: 3),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: _Pill(pill: pill, radius: _radiusFor(context, index)),
            ),
          ],
        ],
      ),
    );
  }

  /// The connective shape: outer radius on the ends, a small one between.
  ///
  /// A selected pill ignores this and goes fully round, which is decided in
  /// [_Pill] so the two radii can be tweened rather than swapped.
  BorderRadius _radiusFor(BuildContext context, int index) {
    final outer = Radius.circular(context.radius(Chrome.cardRadius));
    final inner = Radius.circular(context.radius(5));

    final isFirst = index == 0;
    final isLast = index == pills.length - 1;
    if (isFirst && isLast) return BorderRadius.all(outer);
    if (isFirst) {
      return BorderRadius.only(
        topLeft: outer,
        bottomLeft: outer,
        topRight: inner,
        bottomRight: inner,
      );
    }
    if (isLast) {
      return BorderRadius.only(
        topRight: outer,
        bottomRight: outer,
        topLeft: inner,
        bottomLeft: inner,
      );
    }
    return BorderRadius.all(inner);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.pill, required this.radius});

  final ChromePill pill;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = pill.selected;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Matching `_Segment`: a tap on the live pill is not a selection, so
        // it neither buzzes nor fires a reload of what is already showing.
        if (selected) return;
        HapticFeedback.lightImpact();
        pill.onTap();
      },
      child: AnimatedContainer(
        duration: Chrome.duration,
        curve: Chrome.curve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.15)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: selected
              ? BorderRadius.circular(context.radius(Chrome.pillRadius))
              : radius,
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.onSurface.withValues(alpha: 0.08),
            width: Chrome.pillBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pill.icon != null) ...[
              Icon(
                pill.icon,
                size: 14,
                color: selected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
            ],
            // Only the label gives way. `Flexible` rather than `Expanded`
            // because the row is `min` — an `Expanded` would demand the full
            // capped width for every pill and undo the content sizing.
            Flexible(
              child: Text(
                pill.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (pill.count != null) ...[
              const SizedBox(width: 6),
              Text(
                '${pill.count}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: (selected ? scheme.primary : scheme.onSurfaceVariant)
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
