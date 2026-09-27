import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';

/// Tells the reader that the platform refused to hide this window.
///
/// **This widget exists because the state behind it was dead.** The controller
/// already told apart "applied" from "asked and refused", the commit that
/// added it argued at length that a privacy promise must be reported rather
/// than swallowed — and then nothing rendered either flag, so a refusal was
/// indistinguishable from success on screen. That is the defect this project
/// states outright, shipped inside the change that was arguing against it.
/// Found by `codeant-ai`.
///
/// It is deliberately **not** a snackbar. A snackbar is dismissed by time, and
/// the thing it would be reporting is true for as long as the chapter is open:
/// a reader who looked away for four seconds would be left believing the
/// screenshot block is on. It sits with the chrome instead, so it is there
/// whenever the controls are.
class SecureRefusalNotice extends StatelessWidget {
  const SecureRefusalNotice({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: Chrome.gutter),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(
            context.radius(Chrome.cardRadius),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.warning_2, size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            // Says what is *not* true, rather than that something failed. The
            // reader turned on a setting to stop screenshots; the fact they
            // need is that screenshots are still possible, not that a channel
            // returned false.
            Flexible(
              child: Text(
                'This device would not hide the reader from screenshots.',
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
