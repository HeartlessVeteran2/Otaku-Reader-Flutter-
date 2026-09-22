import 'package:flutter/material.dart';

import 'package:otaku_reader/features/reader/display/reader_display.dart';

/// Wraps the reader's page content in whatever colour treatment is configured.
///
/// **Applied once.** AnymeX applies its colour filter through *two* mechanisms
/// that are both unconditionally in the same `Stack`: `reader_view.dart:206`
/// wraps the content in `ColorFiltered(ColorFilter.mode(colour, blendMode))`,
/// and `reader_view.dart:237` then stacks `ReaderContentOverlay`, whose painter
/// draws the same colour in the same blend mode over the top. Read directly in
/// the reference rather than inferred from its file names — and it is exactly
/// the shape a survey misses, because the two live in different files and only
/// one of them is named after colour.
///
/// What the doubling *renders* was not measured: the obvious pixel probe
/// deadlocks under `flutter test`, because `RenderRepaintBoundary.toImage`
/// cannot complete inside `pumpAndSettle`. So this comment claims the structure
/// it verified and no magnitude it did not — the distinction this repo has paid
/// for. Applying it once is correct regardless of the number.
///
/// Order matters and is deliberate: desaturate or invert the *artwork*, then
/// tint the result. Tinting first and then desaturating would throw the tint
/// away, which is the one ordering that makes the colour control inert.
class ReaderDisplayLayer extends StatelessWidget {
  const ReaderDisplayLayer({
    super.key,
    required this.child,
    this.greyscale = false,
    this.invert = false,
    this.filter,
    this.blend = ReaderBlend.srcOver,
  });

  final Widget child;
  final bool greyscale;
  final bool invert;

  /// Null means no colour filter, which is not the same as a transparent one:
  /// a `ColorFiltered` still allocates a layer.
  final Color? filter;
  final ReaderBlend blend;

  @override
  Widget build(BuildContext context) {
    var content = child;

    // **Composed, where AnymeX makes them exclusive.** Its `reader_view` reads
    // `if (greyscale) … else if (invert) …`, so turning greyscale on silently
    // disables a live invert switch — a control that does nothing, which this
    // file's own rules forbid and which this reader has shipped three times.
    // Composing is also strictly more capable: inverted greyscale is a real
    // night-reading mode, and it is what the exclusive version cannot reach.
    if (greyscale) {
      content = ColorFiltered(
        colorFilter: const ColorFilter.matrix(ReaderMatrices.greyscale),
        child: content,
      );
    }
    if (invert) {
      content = ColorFiltered(
        colorFilter: const ColorFilter.matrix(ReaderMatrices.invert),
        child: content,
      );
    }
    final tint = filter;
    if (tint != null) {
      content = ColorFiltered(
        colorFilter: ColorFilter.mode(tint, blend.mode),
        child: content,
      );
    }
    return content;
  }
}

/// The dimming veil, painted over the page and **under** the chrome.
///
/// That placement is the difference between this and AnymeX's, which stacks its
/// overlay above everything it draws. Dimming the controls along with the page
/// makes the one surface a reader reaches for when the page is too bright the
/// hardest thing on screen to read.
///
/// `IgnorePointer` because a veil that eats taps turns the tap zones off
/// without saying so.
class ReaderDimVeil extends StatelessWidget {
  const ReaderDimVeil({super.key, required this.percent});

  /// `0` to `100`, a positive magnitude. Zero renders **nothing at all** rather
  /// than a transparent box — the same rule as a zero-sigma `BackdropFilter`,
  /// which still saves and composites a layer for no visible effect.
  final int percent;

  @override
  Widget build(BuildContext context) {
    if (percent <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: (percent / 100).clamp(0.0, 1.0),
        child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
      ),
    );
  }
}
