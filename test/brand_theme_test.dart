import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/theme/brand.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';

import 'helpers/isar_test_env.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The hue of a colour in degrees, and how saturated it is (HSL).
({double hue, double saturation}) _hsl(Color c) {
  final hsl = HSLColor.fromColor(c);
  return (hue: hsl.hue, saturation: hsl.saturation);
}

/// The shortest distance between two hues, in degrees.
double _hueGap(double a, double b) {
  final raw = (a - b).abs() % 360;
  return raw > 180 ? 360 - raw : raw;
}

/// Every (surface, text-on-surface) pair the scheme publishes for its accents.
Map<String, (Color, Color)> _pairs(ColorScheme s) => {
  'primary': (s.primary, s.onPrimary),
  'primaryContainer': (s.primaryContainer, s.onPrimaryContainer),
  'secondary': (s.secondary, s.onSecondary),
  'secondaryContainer': (s.secondaryContainer, s.onSecondaryContainer),
  'secondaryFixed': (s.secondaryFixed, s.onSecondaryFixed),
  'tertiary': (s.tertiary, s.onTertiary),
  'tertiaryContainer': (s.tertiaryContainer, s.onTertiaryContainer),
  'tertiaryFixed': (s.tertiaryFixed, s.onTertiaryFixed),
  'surface': (s.surface, s.onSurface),
};

/// The whole secondary family, so a member dropped from the lift is visible.
List<Color> _secondaryFamily(ColorScheme s) => [
  s.secondary,
  s.onSecondary,
  s.secondaryContainer,
  s.onSecondaryContainer,
  s.secondaryFixed,
  s.secondaryFixedDim,
  s.onSecondaryFixed,
  s.onSecondaryFixedVariant,
];

List<Color> _tertiaryFamily(ColorScheme s) => [
  s.tertiary,
  s.onTertiary,
  s.tertiaryContainer,
  s.onTertiaryContainer,
  s.tertiaryFixed,
  s.tertiaryFixedDim,
  s.onTertiaryFixed,
  s.onTertiaryFixedVariant,
];

/// The `primary` family of a single-seeded scheme — what the lift copies over.
List<Color> _primaryFamily(ColorScheme s) => [
  s.primary,
  s.onPrimary,
  s.primaryContainer,
  s.onPrimaryContainer,
  s.primaryFixed,
  s.primaryFixedDim,
  s.onPrimaryFixed,
  s.onPrimaryFixedVariant,
];

ColorScheme _seeded(
  Color seed,
  Brightness brightness,
  DynamicSchemeVariant v,
) => ColorScheme.fromSeed(
  seedColor: seed,
  brightness: brightness,
  dynamicSchemeVariant: v,
);

void main() {
  group('the palette is the artwork, not an approximation of it', () {
    // Pinned because `tool/generate_launcher_icons.py` reads the same artwork
    // for the launcher icon. If someone nudges a constant here by eye, the icon
    // and the UI stop being the same colour and nothing else would notice.
    test('the three inks and the ground are the measured values', () {
      expect(BrandPalette.petal, const Color(0xFFFA60BE));
      expect(BrandPalette.ink, const Color(0xFF313575));
      expect(BrandPalette.blossom, const Color(0xFFE17559));
      expect(BrandPalette.ground, const Color(0xFF0A0A0B));
    });

    // The measured gaps are petal-ink 87 degrees, petal-blossom 49 and
    // ink-blossom 136. The bound is 40 because that is what the artwork
    // actually is: the pink and the coral are neighbours on the wheel, which is
    // why the coral reads as an accent rather than a third voice. Asserting 60
    // here would have been asserting a palette this logo does not have.
    test('the three inks are three distinguishable hues', () {
      final petal = _hsl(BrandPalette.petal).hue;
      final ink = _hsl(BrandPalette.ink).hue;
      final blossom = _hsl(BrandPalette.blossom).hue;
      expect(_hueGap(petal, ink), greaterThan(40));
      expect(_hueGap(petal, blossom), greaterThan(40));
      expect(_hueGap(ink, blossom), greaterThan(40));
    });
  });

  group('each accent family comes from its own ink', () {
    for (final brightness in Brightness.values) {
      test('${brightness.name}: secondary is the navy family, whole', () {
        const variant = kDefaultSchemeVariant;
        final brand = brandColorScheme(
          brightness: brightness,
          variant: variant,
        );
        final navy = _seeded(BrandPalette.ink, brightness, variant);
        final petal = _seeded(BrandPalette.petal, brightness, variant);

        expect(_secondaryFamily(brand), _primaryFamily(navy));
        // ...and that assertion is not vacuous: the pink's own secondary family
        // is a different set of colours, so a member left out of the lift shows
        // up as an inequality rather than passing by coincidence.
        expect(_secondaryFamily(brand), isNot(_secondaryFamily(petal)));
      });

      test('${brightness.name}: tertiary is the coral family, whole', () {
        const variant = kDefaultSchemeVariant;
        final brand = brandColorScheme(
          brightness: brightness,
          variant: variant,
        );
        final coral = _seeded(BrandPalette.blossom, brightness, variant);
        final petal = _seeded(BrandPalette.petal, brightness, variant);

        expect(_tertiaryFamily(brand), _primaryFamily(coral));
        expect(_tertiaryFamily(brand), isNot(_tertiaryFamily(petal)));
      });

      test('${brightness.name}: primary is still seeded from the petal', () {
        const variant = kDefaultSchemeVariant;
        final brand = brandColorScheme(
          brightness: brightness,
          variant: variant,
        );
        final petal = _seeded(BrandPalette.petal, brightness, variant);
        expect(_primaryFamily(brand), _primaryFamily(petal));
      });
    }
  });

  group('the composition is readable at every setting', () {
    // **This is the test the design exists for.**
    //
    // The obvious alternative is `ColorScheme.fromSeed(secondary: navy, …)`,
    // which overrides the finished role colour and leaves `onSecondary` derived
    // from the pink. Measured against the same 18 combinations, that version
    // bottoms out at **1.14** (dark `monochrome`) and **1.30** — and that
    // second one is light `fidelity`, the variant a fresh install actually
    // starts on. So the obvious version does not merely have a bad corner: it
    // ships unreadable secondary text on day one, on the default setting.
    // Lifting whole families never drops below 4.54, because every on-colour
    // was generated by the engine against the colour it sits on.
    //
    // Measured by applying the naive version and reading the failures, not
    // predicted.
    for (final brightness in Brightness.values) {
      for (final variant in DynamicSchemeVariant.values) {
        test('${brightness.name} / ${variant.name} clears WCAG AA', () {
          final scheme = brandColorScheme(
            brightness: brightness,
            variant: variant,
          );
          _pairs(scheme).forEach((role, pair) {
            expect(
              _contrast(pair.$1, pair.$2),
              greaterThanOrEqualTo(4.5),
              reason: '$role in ${brightness.name}/${variant.name}',
            );
          });
        });
      }
    }
  });

  group('the default variant keeps the brand recognisable', () {
    // Asserting the *consequence*, not the setting: `tonalSpot` caps chroma and
    // turns the petal pink into `#874B6C`, a mauve at 28% saturation. Anything
    // that quietly restores it fails here rather than merely looking duller.
    test('the default light primary is saturated, not muted', () {
      final scheme = brandColorScheme(
        brightness: Brightness.light,
        variant: kDefaultSchemeVariant,
      );
      expect(_hsl(scheme.primary).saturation, greaterThan(0.5));
    });

    test('the default light primary is still a magenta', () {
      final scheme = brandColorScheme(
        brightness: Brightness.light,
        variant: kDefaultSchemeVariant,
      );
      expect(
        _hueGap(_hsl(scheme.primary).hue, _hsl(BrandPalette.petal).hue),
        lessThan(30),
      );
    });
  });

  group('a seed that is not the brand does not get the brand', () {
    IsarTestEnv? env;
    setUpAll(
      () async =>
          env = await IsarTestEnv.open('brand', db.AppDatabaseSchemas.all),
    );
    tearDownAll(() async => env?.close());

    late ThemeController theme;
    setUp(() {
      env!.clear();
      Get.reset();
      theme = Get.put<ThemeController>(ThemeController());
    });

    const green = Color(0xFF2E7D32);

    ColorScheme schemeOf(ThemeController c) =>
        c.theme(Brightness.light).colorScheme;

    test('a fresh install is the brand', () {
      expect(theme.usesBrandPalette, isTrue);
      expect(theme.seedColor, BrandPalette.petal);
      expect(
        schemeOf(theme).secondary,
        _seeded(
          BrandPalette.ink,
          Brightness.light,
          kDefaultSchemeVariant,
        ).primary,
      );
    });

    test('a custom colour is that colour alone — no navy, no coral', () {
      theme.setCustomColor(green);
      theme.setSource(ThemeSource.custom);

      expect(theme.usesBrandPalette, isFalse);
      final scheme = schemeOf(theme);
      final plain = _seeded(green, Brightness.light, kDefaultSchemeVariant);
      expect(scheme.secondary, plain.secondary);
      expect(scheme.tertiary, plain.tertiary);
      expect(
        scheme.secondary,
        isNot(
          _seeded(
            BrandPalette.ink,
            Brightness.light,
            kDefaultSchemeVariant,
          ).primary,
        ),
      );
    });

    test('a cover tint is that cover alone — no navy, no coral', () {
      theme.setUseCoverColor(true);
      theme.applyCoverSeed(green);

      expect(theme.usesBrandPalette, isFalse);
      final scheme = schemeOf(theme);
      final plain = _seeded(green, Brightness.light, kDefaultSchemeVariant);
      expect(scheme.secondary, plain.secondary);
      expect(scheme.tertiary, plain.tertiary);
    });

    test('a cover tint that comes back empty falls back to the brand', () {
      theme.setUseCoverColor(true);
      theme.applyCoverSeed(green);
      theme.applyCoverSeed(null);

      expect(theme.usesBrandPalette, isTrue);
      expect(theme.seedColor, BrandPalette.petal);
    });
  });
}
