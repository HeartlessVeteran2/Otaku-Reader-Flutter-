import 'dart:async';

import 'package:flutter/material.dart';

/// Briefly blanks the screen after a page turn, to clear e-ink ghosting.
///
/// An electrophoretic display leaves a faint impression of the previous frame
/// behind, and the fix every e-reader uses is a full-screen flash that drives
/// every particle to one pole and back. There is nothing to ask the platform
/// for — on a phone-shaped device Flutter has no idea it is driving e-ink — so
/// this *is* the feature: paint the whole surface opaque for a moment.
///
/// Two decisions worth keeping:
///
/// - **It is driven by [page], not by a timer.** Ghosting is caused by a frame
///   changing, so a flash on a schedule fires while the reader is sitting
///   still on one panel and does not fire on the turn that caused the ghost.
///   A `didUpdateWidget` comparison is the whole trigger.
/// - **It does not flash on the first build**, and that is structural rather
///   than guarded: `didUpdateWidget` does not run on the first build at all.
///   Opening a chapter is already a full repaint and a flash there reads as
///   the app glitching on open, so the first *turn* is the first flash.
///
/// At zero duration it renders nothing at all rather than a zero-length
/// animation — the same rule as `ChromeCard` dropping a zero-sigma
/// `BackdropFilter` and `ReaderDimVeil` returning `SizedBox.shrink()`: at
/// zero, remove the effect rather than scale it to zero.
class EInkFlash extends StatefulWidget {
  const EInkFlash({
    super.key,
    required this.page,
    required this.enabled,
    required this.duration,
    this.color = Colors.black,
  });

  /// The reader's current page. A change is what fires the flash.
  final int page;
  final bool enabled;
  final Duration duration;
  final Color color;

  @override
  State<EInkFlash> createState() => _EInkFlashState();
}

class _EInkFlashState extends State<EInkFlash> {
  bool _flashing = false;
  Timer? _timer;

  @override
  void didUpdateWidget(EInkFlash old) {
    super.didUpdateWidget(old);
    // Compared against `old.page`, deliberately, rather than against a field
    // this State keeps. The field version is the one that suggests itself and
    // it does not work: `late int _previous = widget.page` is initialised on
    // **first read**, and the first read is this very comparison — by which
    // time `widget` is already the new one, so it initialises to the new page,
    // compares equal, and the flash never fires at all. Measured: six of these
    // tests failed on it. `didUpdateWidget` is handed the previous widget for
    // exactly this reason, so there is no state to get wrong.
    if (widget.page == old.page) return;
    if (!widget.enabled || widget.duration <= Duration.zero) return;
    _flash();
  }

  void _flash() {
    _timer?.cancel();
    setState(() => _flashing = true);
    _timer = Timer(widget.duration, () {
      // The reader can close inside the window — the flash is short but a page
      // turn is exactly when someone backs out.
      if (mounted) setState(() => _flashing = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_flashing) return const SizedBox.shrink();
    // `IgnorePointer`, because a tap during the flash belongs to the page
    // underneath. The flash is feedback, not a modal — and at 120ms a
    // swallowed tap is a page turn the reader has to make twice.
    return IgnorePointer(
      child: ColoredBox(color: widget.color, child: const SizedBox.expand()),
    );
  }
}
