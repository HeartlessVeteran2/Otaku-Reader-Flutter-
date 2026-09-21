import 'package:flutter/material.dart';

/// How round, how glowing and how blurred the chrome is, as a user setting.
///
/// Ported from AnymeX's `UIMultiplierExtension`
/// (`lib/controllers/settings/methods.dart`), which gives every `num` a
/// `multiplyRadius()` / `multiplyGlow()` / `multiplyBlur()` resolving
/// `Get.find<Settings>()` per call. The idea is theirs and it is a good one:
/// the whole app's roundness becomes one slider rather than thirty hardcoded
/// numbers. `CLAUDE.md` has said so since the chrome landed, and it was not
/// adopted until now.
///
/// **The mechanism is deliberately not theirs**, and the reason is measured
/// rather than stylistic. `Get.find` inside a `num` extension makes every
/// radius a DI lookup, so any widget that draws a rounded corner needs a
/// registered controller — and `test/chrome_test.dart` renders 35 tests'
/// worth of chrome primitives with **no** GetX registrations at all. The two
/// ways out are both worse than this one: making those suites register a
/// controller couples a layout test to app wiring, and giving the lookup a
/// silent 1.0 fallback is the `ChromeHeaderScope.of` trap recorded in
/// `CLAUDE.md` — a default that is right for one caller and quietly wrong for
/// every other.
///
/// A `ThemeExtension` has neither problem: it rides the `ThemeData` the app
/// already builds, every widget already has the `BuildContext` to read it,
/// and a test that builds a bare `MaterialApp` gets [ChromeMetrics.standard]
/// without being told to.
///
/// The other thing that made this cheap: **not one of the 17 call sites was
/// in a `const` context**, measured before writing any of it, so making the
/// numbers non-const costs nothing. Had they been const, this would have been
/// a much larger change and worth pricing differently.
@immutable
class ChromeMetrics extends ThemeExtension<ChromeMetrics> {
  const ChromeMetrics({
    required this.radiusScale,
    required this.glowScale,
    required this.blurScale,
  });

  /// Every multiplier at 1.0 — the shapes exactly as `Chrome` declares them.
  ///
  /// This is what an unconfigured build and every widget test gets, so the
  /// tokens keep meaning what their own documentation says by default.
  static const standard = ChromeMetrics(
    radiusScale: 1,
    glowScale: 1,
    blurScale: 1,
  );

  /// AnymeX's own slider bounds, kept so a value that works there works here.
  /// Zero is a real setting on all three: square corners, no glow, no blur.
  static const minScale = 0.0;
  static const maxRadiusScale = 3.0;
  static const maxGlowScale = 5.0;
  static const maxBlurScale = 5.0;

  final double radiusScale;
  final double glowScale;
  final double blurScale;

  @override
  ChromeMetrics copyWith({
    double? radiusScale,
    double? glowScale,
    double? blurScale,
  }) => ChromeMetrics(
    radiusScale: radiusScale ?? this.radiusScale,
    glowScale: glowScale ?? this.glowScale,
    blurScale: blurScale ?? this.blurScale,
  );

  /// Lerped rather than snapped, so changing a slider animates with the rest
  /// of the theme instead of popping.
  @override
  ChromeMetrics lerp(ThemeExtension<ChromeMetrics>? other, double t) {
    if (other is! ChromeMetrics) return this;
    return ChromeMetrics(
      radiusScale: _lerp(radiusScale, other.radiusScale, t),
      glowScale: _lerp(glowScale, other.glowScale, t),
      blurScale: _lerp(blurScale, other.blurScale, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) =>
      other is ChromeMetrics &&
      other.radiusScale == radiusScale &&
      other.glowScale == glowScale &&
      other.blurScale == blurScale;

  @override
  int get hashCode => Object.hash(radiusScale, glowScale, blurScale);
}

/// Reads [ChromeMetrics] off the theme and applies it to one of `Chrome`'s
/// tokens.
///
/// `context.radius(Chrome.cardRadius)` is as close to AnymeX's
/// `16.multiplyRadius()` as this app's shape allows, and it is one call rather
/// than a lookup plus a multiply at every site.
extension ChromeMetricsX on BuildContext {
  ChromeMetrics get chromeMetrics =>
      Theme.of(this).extension<ChromeMetrics>() ?? ChromeMetrics.standard;

  /// A corner radius, scaled. Never negative: a slider at 0 means square.
  double radius(double base) =>
      (base * chromeMetrics.radiusScale).clamp(0.0, double.infinity);

  /// A shadow's spread, scaled.
  double glow(double base) =>
      (base * chromeMetrics.glowScale).clamp(0.0, double.infinity);

  /// A `BackdropFilter` sigma, scaled.
  ///
  /// Clamped away from exactly 0 when the base is non-zero, because
  /// `ImageFilter.blur(sigmaX: 0)` is a real filter that still costs a saved
  /// layer — a user who turns blur off should pay nothing for it, which the
  /// call site handles by dropping the filter entirely at 0.
  double blur(double base) =>
      (base * chromeMetrics.blurScale).clamp(0.0, double.infinity);
}

/// A shadow under both multipliers, or no shadow at all.
///
/// **The two sliders split it, as AnymeX's do:** *Blur* scales the shadow's
/// blur radius, *Glow* scales its spread. Chosen by the developer over this
/// app's first answer, which scaled both off `glowScale` and kept `blurScale`
/// for the `BackdropFilter` alone.
///
/// A free function for the same reason AnymeX's `glowingShadow` /
/// `lightGlowingShadow` are: the *remove it at zero* rule has to live in one
/// place. Left to each call site, one of them eventually scales to zero
/// instead of dropping out, and the defect is invisible in the diff.
///
/// ### Why **either** multiplier at zero removes it
///
/// Splitting the two inputs creates a case AnymeX has and gets wrong, so this
/// is a port with a correction rather than a copy:
///
/// - **Glow at 0** must mean no glow — that is what the slider is called. Left
///   to the arithmetic it would only zero the *spread*, and a 50px blur with
///   no spread is still a plainly visible bloom.
/// - **Blur at 0** would leave blur radius 0 with a positive spread, which is
///   a **hard rectangle** behind the surface: not a subtle shadow, a solid
///   band. `glowingShadow` guards only its glow multiplier, so AnymeX paints
///   exactly that when its blur slider bottoms out.
///
/// So the honest reading of the labels is that each slider at 0 removes the
/// thing it names, and a shadow needs both to exist. The consequence worth
/// knowing: **Blur at 0 now also takes the drop shadows**, not just the
/// frosted glass.
///
/// Returns `null` rather than an empty list so it drops straight into
/// `BoxDecoration.boxShadow`, whose own "none" is null.
List<BoxShadow>? glowShadow(
  BuildContext context, {
  required Color color,
  required double blurRadius,
  double spreadRadius = 0,
  Offset offset = Offset.zero,
}) {
  if (context.glow(1) <= 0 || context.blur(1) <= 0) return null;
  return [
    BoxShadow(
      color: color,
      blurRadius: context.blur(blurRadius),
      spreadRadius: context.glow(spreadRadius),
      offset: offset,
    ),
  ];
}
