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
