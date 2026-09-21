import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/ui/greeting_controller.dart';

/// The greeting line, listening for itself.
///
/// Passed as `ChromeScaffold.subtitleWidget` rather than as a `String`
/// subtitle, because the phrase changes on a clock rather than on a rebuild:
/// a screen sitting open at 16:59 has to say "Good evening" at 17:00 without
/// anything else prompting it. A `String` read at build time would be right
/// most of the time and quietly wrong across every boundary — and it would
/// leave `GreetingController`'s timer with no observer, which is the defect
/// this project has now shipped three times in other clothes.
///
/// It inherits its colour and size from the header's `DefaultTextStyle`, so
/// the two cannot disagree about what a subtitle looks like.
class GreetingText extends StatelessWidget {
  const GreetingText({super.key});

  @override
  Widget build(BuildContext context) {
    // Nothing rather than a throw when the controller is not registered: a
    // greeting is decoration, and a screen test has no business standing one
    // up. `app_bindings_test` asserts the app itself registers it, so an
    // empty greeting cannot ship unnoticed.
    if (!Get.isRegistered<GreetingController>()) return const SizedBox.shrink();
    final greeting = Get.find<GreetingController>();
    return Obx(
      () => Text(
        greeting.text.value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
