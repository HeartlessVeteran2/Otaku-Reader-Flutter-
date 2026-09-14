import 'package:flutter/material.dart';

import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';

/// What the user asked to change. Null means "leave it alone".
///
/// The whole point of the type: AniList's mutation writes exactly what it is
/// given, so a field the user never touched must not be sent. Sending the
/// value the sheet opened with would write back a number read minutes ago and
/// quietly undo progress made on another device in between.
class AniListEdit {
  const AniListEdit({this.status, this.progress});

  final AniListListStatus? status;
  final int? progress;

  bool get isEmpty => status == null && progress == null;
}

/// Edits the viewer's AniList row, or creates it.
///
/// One sheet for both, because `SaveMediaListEntry` creates the row when there
/// is none — so "add to list" is just an edit that starts from blank.
Future<AniListEdit?> showAniListEditSheet(
  BuildContext context, {
  required AniListListResult result,
  int? totalChapters,
}) => showModalBottomSheet<AniListEdit>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(OneUi.radius)),
  ),
  builder: (_) => _EditSheet(result: result, totalChapters: totalChapters),
);

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.result, this.totalChapters});

  final AniListListResult result;
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

  /// What actually changed, which is what gets sent.
  AniListEdit get _edit => AniListEdit(
    status: _status == null || _status == _original?.status ? null : _status,
    progress: _progress == _original?.progress ? null : _progress,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.totalChapters;

    return Padding(
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
                // Capped at the known total, where there is one. A count past
                // the last chapter is not something AniList can mean.
                onPressed: total != null && _progress >= total
                    ? null
                    : () => setState(() => _progress++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
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
    );
  }
}
