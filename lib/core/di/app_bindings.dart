import 'package:get/get.dart';

import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/repository/extension_repository_impl.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/data/repository/source_repository_impl.dart';
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';

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

    // Repositories are registered against their *interfaces*, so nothing in the
    // feature layer can reach an implementation detail such as Isar or the
    // interpreter. They are permanent because the source repository caches live
    // runtimes: letting GetX dispose it would silently throw away parsed
    // extension scripts every time the last screen using one closed.
    Get.put<ExtensionRepository>(ExtensionRepositoryImpl(), permanent: true);
    Get.put<SourceRepository>(SourceRepositoryImpl(), permanent: true);
    Get.put<LibraryRepository>(LibraryRepositoryImpl(), permanent: true);

    // lazyPut, so the catalogue is not read until the Browse tab is first
    // opened. The shell builds its tabs lazily for the same reason.
    Get.lazyPut<ExtensionsController>(
      () => ExtensionsController(
        extensions: Get.find<ExtensionRepository>(),
        sources: Get.find<SourceRepository>(),
      ),
      fenix: true,
    );
    Get.lazyPut<LibraryController>(
      () => LibraryController(library: Get.find<LibraryRepository>()),
      fenix: true,
    );
  }
}
