import 'dart:convert';

/// What a tap in a zone does.
///
/// **Six, where AnymeX has eight**, and the two it loses are the reason its
/// editor needs a per-mode filter at all. Its set splits `nextPage`/`prevPage`
/// from `scrollUp`/`scrollDown`, so the editor has to hide the pair that does
/// not apply to the layout being edited — and a zone carrying the wrong one is
/// a dead zone with nothing to say so.
///
/// [next] and [previous] mean *one unit of reading order*, which the reader
/// resolves per layout: a page turn in paged mode, a screen in continuous. The
/// filter then has nothing to filter, which is a whole class of mistake removed
/// rather than guarded.
///
/// The axis-free naming is also forced by this app having four directions where
/// AnymeX's zones assume two: "scroll up" means nothing in a strip read from
/// the right.
enum ReaderAction {
  next,
  previous,
  nextChapter,
  previousChapter,
  toggleChrome,
  none;

  /// What the editor and the reader both call this.
  ///
  /// On the enum for the reason `ReadingDirection.label` is: two screens render
  /// it, and a pair that disagrees is a tooltip contradicting the row that set
  /// it.
  String get label => switch (this) {
    ReaderAction.next => 'Next page',
    ReaderAction.previous => 'Previous page',
    ReaderAction.nextChapter => 'Next chapter',
    ReaderAction.previousChapter => 'Previous chapter',
    ReaderAction.toggleChrome => 'Show or hide the controls',
    ReaderAction.none => 'Nothing',
  };
}

/// One band across the reading axis, and what tapping it does.
///
/// [fraction] is a share of the axis rather than a pixel span, so a profile
/// means the same thing on every screen and cannot be authored into a gap.
class TapBand {
  const TapBand(this.fraction, this.action);

  final double fraction;
  final ReaderAction action;

  Map<String, dynamic> toJson() => {'f': fraction, 'a': action.index};

  /// Returns null rather than throwing on anything it does not recognise.
  ///
  /// The row is a stored preference, read on the way into the reader — a throw
  /// there is a chapter that will not open, and the honest answer to a row this
  /// build cannot read is the default profile. An index from a *newer* build is
  /// the realistic case, and `ReaderAction.values[...]` would range-error on it.
  static TapBand? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final fraction = raw['f'];
    final action = raw['a'];
    if (fraction is! num || action is! int) return null;
    if (action < 0 || action >= ReaderAction.values.length) return null;
    if (fraction <= 0 || fraction > 1) return null;
    return TapBand(fraction.toDouble(), ReaderAction.values[action]);
  }
}

/// The bands a tap is resolved against, for one reading layout.
///
/// Ported from AnymeX's `TapZoneLayout` with its geometry replaced. AnymeX
/// stores each zone as a normalised `Rect` and its editor can only ever change
/// the *action* — `_editZone` rebuilds the zone with `bounds: zone.bounds` — so
/// the rectangles are free-form in the format and fixed in practice. Free-form
/// rectangles can also overlap or leave a gap, and AnymeX resolves the first by
/// walking its list backwards so the last match wins; the second it cannot
/// resolve at all, and a tap in a gap silently does nothing.
///
/// Bands that are shares of one axis cannot gap or overlap **by construction**,
/// which is the Kotlin Otaku-Reader's shape (`TapZoneConfig`, whose `init`
/// requires its three widths to sum to 1). It is also the geometry a phone can
/// actually be asked to edit: three numbers on sliders, not four corners under
/// a fingertip.
class TapZoneProfile {
  TapZoneProfile(List<TapBand> bands) : bands = List.unmodifiable(bands);

  final List<TapBand> bands;

  /// How far the fractions may stray from 1 before a profile is rejected.
  ///
  /// Slider arithmetic does not land on exact thirds, and a profile refused for
  /// a rounding error falls back to the default and silently discards what the
  /// user set. The Kotlin app uses the same tolerance for the same reason.
  static const tolerance = 0.001;

  bool get isValid =>
      bands.isNotEmpty &&
      (bands.fold<double>(0, (sum, b) => sum + b.fraction) - 1).abs() <
          tolerance;

  /// The action for a tap at [position], a fraction of the way along the
  /// reading axis measured **from the leading edge**.
  ///
  /// Leading, not left. That is the whole of the right-to-left correction: the
  /// caller mirrors the position for a reversed direction, so the band the user
  /// authored as "the side you tap to go on" stays the side you tap to go on.
  /// AnymeX gets this wrong in a way that is invisible in its own source —
  /// `_navNextPage` and `_navPrevPage` walk the page index with no reference to
  /// `readingDirection.reversed`, so its default profile fires *previous* for a
  /// tap on the leading side of every right-to-left manga, which is most manga.
  ReaderAction actionAt(double position) {
    var edge = 0.0;
    for (final band in bands) {
      edge += band.fraction;
      if (position < edge) return band.action;
    }
    // Only reachable at exactly 1.0, or for fractions summing a hair under it.
    return bands.isEmpty ? ReaderAction.none : bands.last.action;
  }

  String encode() => jsonEncode(bands.map((b) => b.toJson()).toList());

  /// Returns null for anything it cannot read, so the caller falls back to a
  /// default rather than opening a reader with no working taps.
  static TapZoneProfile? decode(String? raw) {
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;
    final bands = <TapBand>[];
    for (final entry in decoded) {
      final band = TapBand.fromJson(entry);
      if (band == null) return null;
      bands.add(band);
    }
    final profile = TapZoneProfile(bands);
    return profile.isValid ? profile : null;
  }

  /// AnymeX's own default, which is the same for both layouts once the actions
  /// are axis-free: a third to go back, a third for the controls, a third to go
  /// on. Its four profiles differ only in which axis they are measured along
  /// and which of its two action pairs they use, and both of those are now
  /// properties of the reader rather than of the profile.
  static TapZoneProfile get standard => TapZoneProfile(const [
    TapBand(0.3, ReaderAction.previous),
    TapBand(0.4, ReaderAction.toggleChrome),
    TapBand(0.3, ReaderAction.next),
  ]);
}
