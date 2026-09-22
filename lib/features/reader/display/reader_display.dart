import 'package:flutter/material.dart';

/// What the reader paints behind a page.
///
/// AnymeX's four, ported at its own values (`reader_view.dart:170-175`). Worth
/// noting against `FEATURES.md`, which claimed **nine**: that number is
/// Komikku's, and it reached this repo's checklist without anyone checking the
/// reference it was filed under. Four is what the blueprint has.
///
/// Persisted as `index`, so this may only be appended to — the rule
/// `ReadingDirection` carries for the same reason.
enum ReaderBackground {
  black,
  white,
  grey,
  system;

  String get label => switch (this) {
    ReaderBackground.black => 'Black',
    ReaderBackground.white => 'White',
    ReaderBackground.grey => 'Grey',
    ReaderBackground.system => 'Match the app',
  };

  /// Resolved against the theme, because `system` has no fixed colour.
  Color colorFor(BuildContext context) => switch (this) {
    ReaderBackground.black => Colors.black,
    ReaderBackground.white => Colors.white,
    ReaderBackground.grey => const Color(0xFF303030),
    ReaderBackground.system => Theme.of(context).scaffoldBackgroundColor,
  };
}

/// The blend modes a colour filter may use.
///
/// AnymeX's sixteen in AnymeX's order, because the **index is persisted** and
/// its `_blendModeFromIndex` is the shape a stored value was written against.
/// Re-ordering them to something tidier would silently re-point every stored
/// filter — the `ReadingDirection` rule again, and the reason that one is
/// written down.
///
/// An out-of-range index falls back rather than throwing: a filter mode from a
/// newer build must leave the page readable, not stop the chapter opening.
enum ReaderBlend {
  srcOver(BlendMode.srcOver, 'Normal'),
  multiply(BlendMode.multiply, 'Multiply'),
  screen(BlendMode.screen, 'Screen'),
  overlay(BlendMode.overlay, 'Overlay'),
  darken(BlendMode.darken, 'Darken'),
  lighten(BlendMode.lighten, 'Lighten'),
  colorDodge(BlendMode.colorDodge, 'Colour dodge'),
  colorBurn(BlendMode.colorBurn, 'Colour burn'),
  hardLight(BlendMode.hardLight, 'Hard light'),
  softLight(BlendMode.softLight, 'Soft light'),
  difference(BlendMode.difference, 'Difference'),
  exclusion(BlendMode.exclusion, 'Exclusion'),
  hue(BlendMode.hue, 'Hue'),
  saturation(BlendMode.saturation, 'Saturation'),
  color(BlendMode.color, 'Colour'),
  luminosity(BlendMode.luminosity, 'Luminosity');

  const ReaderBlend(this.mode, this.label);

  final BlendMode mode;
  final String label;

  static ReaderBlend fromIndex(int index) =>
      index >= 0 && index < values.length ? values[index] : srcOver;
}

/// The colour matrices, kept here rather than inline so both can be asserted.
abstract final class ReaderMatrices {
  /// Rec. 709 luma weights — the same three AnymeX uses.
  static const greyscale = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const invert = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];
}
