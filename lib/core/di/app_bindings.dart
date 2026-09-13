import 'package:get/get.dart';

import 'package:otaku_reader/core/theme/theme_controller.dart';

/// Explicit dependency wiring.
///
/// AnymeX registers everything in one flat `Get.put` block whose *order* is
/// load-bearing, because its controllers call `Get.find` inside field
/// initializers — adding a controller in the wrong place throws at startup with
/// no indication why. Registering through a Bindings class and constructing
/// dependencies lazily keeps the graph explicit instead.
class AppBindings extends Bindings {
  @override
  void dependencies() {
    Get.put<ThemeController>(ThemeController(), permanent: true);
  }
}
