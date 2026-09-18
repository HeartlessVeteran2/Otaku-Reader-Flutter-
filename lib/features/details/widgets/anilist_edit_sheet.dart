import 'package:flutter/material.dart';

import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';

/// What the user asked to change. Null means "leave it alone".
///
/// The whole point of the type: AniList's mutation writes exactly what it is
/// given, so a field the user never touched must not be sent. Sending the
/// value the sheet opened with would write back a number read minutes ago and
/// quietly undo progress made on another device in between.
class AniListEdit {
  const AniListEdit({this.status, this.progress, this.score});

  final AniListListStatus? status;
  final int? progress;

  /// Null to leave the rating alone; **zero to remove it**. AniList's schema
  /// spells that out — `0 => No Score` — so the two are different requests
  /// and only one of them is "no".
  final double? score;

  bool get isEmpty => status == null && progress == null && score == null;
}

/// Edits the viewer's AniList row, or creates it.
///
/// One sheet for both, because `SaveMediaListEntry` creates the row when there
/// is none — so "add to list" is just an edit that starts from blank.
///
/// [scoreFormat] is the viewer's own display format. Null means there is no
/// viewer to have one — a sign-out that landed between the lookup and this
/// call — and the score control is then left out rather than guessed at,
/// because the same stored rating is 85, 8.5, 8, four stars or a smiley
/// depending on it.
Future<AniListEdit?> showAniListEditSheet(
  BuildContext context, {
  required AniListListResult result,
  required ScoreFormat? scoreFormat,
  int? totalChapters,
}) => showModalBottomSheet<AniListEdit>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(OneUi.radius)),
  ),
  builder: (_) => _EditSheet(
    result: result,
    scoreFormat: scoreFormat,
    totalChapters: totalChapters,
  ),
);

class _EditSheet extends StatefulWidget {
  const _EditSheet({
    required this.result,
    required this.scoreFormat,
    this.totalChapters,
  });

  final AniListListResult result;
  final ScoreFormat? scoreFormat;
  final int? totalChapters;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final AniListListEntry? _original = widget.result.entry;

  /// Seeded from the existing row, or from a sensible default for a manga
  /// being added: somebody opening this on an untracked series is almost
  /// always starting it.
  ///
  /// **Null when the row carries a status this build does not recognise.**
  /// Falling back to "Reading" there would preselect a value the user never
  /// chose, enable Save the instant the sheet opened, and overwrite a status
  /// AniList added after this build shipped. The model already refuses that
  /// fallback for exactly this reason — this is the same rule, one file over,
  /// where it was missed the first time.
  late AniListListStatus? _status = _original == null
      ? AniListListStatus.current
      : _original.status;
  late int _progress = _original?.progress ?? 0;

  /// The working rating, always on the format's own grid.
  ///
  /// The clamp is **defence against a malformed row, not a scale converter**,
  /// and the difference matters: clamping an 85/100 to 5 stars does not
  /// preserve that rating, it destroys it. The scale mismatch it used to
  /// paper over is fixed where it starts — the lookup asks AniList for the
  /// live score format in the same response as the row, so the number and
  /// its units always come from the same moment. What is left here is a
  /// value AniList should never send, kept in range so the input can still
  /// render rather than throwing inside a build.
  late double _score =
      widget.scoreFormat?.clampScore(_original?.score ?? 0) ?? 0;

  /// Whether the user moved the rating at all.
  ///
  /// A flag rather than comparing against the seed, and deliberately: the
  /// clamp above can *itself* change the value, and a value compare would read
  /// that as an edit — arming Save with a number the user never chose, which
  /// is the same defect the unknown-status rule exists to prevent one field
  /// up. Only a touch counts as a touch.
  ///
  /// It guards a path that should now be unreachable, which is the point: if
  /// a malformed row ever does get clamped, the failure is a disabled Save
  /// rather than a silent overwrite.
  bool _scoreTouched = false;

  /// What actually changed, which is what gets sent.
  AniListEdit get _edit => AniListEdit(
    status: _status == null || _status == _original?.status ? null : _status,
    progress: _progress == _original?.progress ? null : _progress,
    score: _scoreTouched ? _score : null,
  );

  void _setScore(double value) {
    final format = widget.scoreFormat;
    if (format == null) return;
    setState(() {
      _score = format.clampScore(value);
      _scoreTouched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.totalChapters;
    final format = widget.scoreFormat;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          OneUi.gutter,
          0,
          OneUi.gutter,
          MediaQuery.viewInsetsOf(context).bottom + OneUi.gutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _original == null ? 'Add to your AniList' : 'Edit your AniList',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: OneUi.sectionGap),
            Text('Status', style: theme.textTheme.labelLarge),
            if (_status == null && _original != null) ...[
              const SizedBox(height: 4),
              Text(
                'AniList calls this "${_original.statusLabel}", which this '
                'version does not know. Pick one to change it, or leave it '
                'alone.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in AniListListStatus.values)
                  ChoiceChip(
                    label: Text(status.label),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: OneUi.sectionGap),
            Text('Chapters read', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filledTonal(
                  // Labelled, and not only for the tests: this sheet now has
                  // two identical +/- pairs, and a screen reader announcing
                  // both as "add" cannot tell a chapter from a rating.
                  tooltip: 'One fewer chapter',
                  // Never below zero: AniList would reject it, and the failure
                  // would arrive as a snackbar long after the tap that caused
                  // it.
                  onPressed: _progress == 0
                      ? null
                      : () => setState(() => _progress--),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Text(
                    total == null ? '$_progress' : '$_progress / $total',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'One more chapter',
                  // Capped at the known total, where there is one. A count past
                  // the last chapter is not something AniList can mean.
                  onPressed: total != null && _progress >= total
                      ? null
                      : () => setState(() => _progress++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            // Left out entirely when the format is unknown. There is no
            // neutral default to fall back on — every format writes a
            // different number for the same rating.
            if (format != null) ...[
              const SizedBox(height: OneUi.sectionGap),
              Text('Score', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _ScoreField(format: format, score: _score, onChanged: _setScore),
            ],
            const SizedBox(height: OneUi.sectionGap),
            // Low, not top-right: the confirm on a sheet belongs where a thumb
            // already is.
            FilledButton(
              // Disabled when nothing changed, so the sheet cannot fire a write
              // that would only re-send what AniList already holds.
              onPressed: _edit.isEmpty
                  ? null
                  : () => Navigator.pop(context, _edit),
              child: Text(_original == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rating input, in whichever shape the viewer's format calls for.
///
/// Three shapes rather than one, because AniList's own schema asks for them by
/// name: `POINT_5` is "An integer from 0-5. Should be represented in Stars"
/// and `POINT_3` "An integer from 0-3. Should be represented in Smileys".
/// Rendering either as a number would show the user a scale their profile has
/// never displayed.
class _ScoreField extends StatelessWidget {
  const _ScoreField({
    required this.format,
    required this.score,
    required this.onChanged,
  });

  final ScoreFormat format;
  final double score;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (format) {
      case ScoreFormat.point5:
        return _Symbols(
          score: score,
          count: 5,
          onChanged: onChanged,
          iconFor: (value, filled) =>
              filled ? Icons.star_rounded : Icons.star_border_rounded,
          labelFor: (value) => '$value ${value == 1 ? 'star' : 'stars'}',
        );
      case ScoreFormat.point3:
        // AniList's own mapping, quoted from the schema: 1 => :(, 2 => :|,
        // 3 => :). Not invented, and not reordered.
        return _Symbols(
          score: score,
          count: 3,
          onChanged: onChanged,
          iconFor: (value, filled) => switch (value) {
            1 =>
              filled
                  ? Icons.sentiment_dissatisfied
                  : Icons.sentiment_dissatisfied_outlined,
            2 =>
              filled
                  ? Icons.sentiment_neutral
                  : Icons.sentiment_neutral_outlined,
            _ =>
              filled
                  ? Icons.sentiment_satisfied
                  : Icons.sentiment_satisfied_outlined,
          },
          labelFor: (value) => switch (value) {
            1 => 'Bad',
            2 => 'Okay',
            _ => 'Good',
          },
        );
      case ScoreFormat.point100:
      case ScoreFormat.point10:
      case ScoreFormat.point10Decimal:
        return _Numeric(format: format, score: score, onChanged: onChanged);
    }
  }
}

/// Stars or smileys: pick one, or clear it.
///
/// Only one symbol is *selected* rather than a filled run, because POINT_3's
/// smileys are three different faces and "all faces up to :|" means nothing.
/// Stars read as a run and are filled that way; the selected value is the same
/// number either way.
class _Symbols extends StatelessWidget {
  const _Symbols({
    required this.score,
    required this.count,
    required this.onChanged,
    required this.iconFor,
    required this.labelFor,
  });

  final double score;
  final int count;
  final ValueChanged<double> onChanged;
  final IconData Function(int value, bool filled) iconFor;
  final String Function(int value) labelFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = score.round();
    // Stars fill cumulatively; faces do not. Five symbols means stars.
    final cumulative = count == 5;

    // A `Wrap`, not a `Row` with a `Spacer`. Five 48px targets and the clear
    // button need about 330px, which a 320px phone does not have between the
    // sheet's gutters — a Row overflows there by 89px and renders the rating
    // control unusable at exactly the width where space is tightest. A Wrap
    // cannot overflow; it moves the clear button to its own line instead.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var value = 1; value <= count; value++)
              IconButton(
                tooltip: labelFor(value),
                onPressed: () => onChanged(value.toDouble()),
                color: theme.colorScheme.primary,
                icon: Icon(
                  iconFor(
                    value,
                    cumulative ? value <= selected : value == selected,
                  ),
                ),
              ),
          ],
        ),
        TextButton(
          // Zero is a real request — "remove my score" — not an empty one, so
          // it needs somewhere to be pressed. On the numeric formats the
          // slider already reaches it; here nothing else does.
          onPressed: selected == 0 ? null : () => onChanged(0),
          child: const Text('No score'),
        ),
      ],
    );
  }
}

/// The numeric formats: a readout, a step either way, and a slider for
/// crossing the range without ninety taps.
class _Numeric extends StatelessWidget {
  const _Numeric({
    required this.format,
    required this.score,
    required this.onChanged,
  });

  final ScoreFormat format;
  final double score;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Lower score',
              onPressed: score <= 0
                  ? null
                  : () => onChanged(score - format.step),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                // Zero is not a rating of zero, and saying "0" would claim it
                // is. AniList's schema calls it No Score; so does this.
                score == 0
                    ? 'No score'
                    : '${format.format(score)} / ${format.format(format.max)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Raise score',
              onPressed: score >= format.max
                  ? null
                  : () => onChanged(score + format.step),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Slider(
          value: score,
          max: format.max,
          // Every stop lands on a value AniList accepts, which is the whole
          // reason this is not a free slider.
          divisions: format.divisions,
          label: score == 0 ? 'No score' : format.format(score),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
