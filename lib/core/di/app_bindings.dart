import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import 'package:otaku_reader/core/platform/network_status.dart';
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/ui/greeting_controller.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/data/repository/extension_repository_impl.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/data/repository/anilist_repository_impl.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/data/repository/source_repository_impl.dart';
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';
import 'package:otaku_reader/data/repository/category_repository_impl.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/features/home/controllers/home_controller.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';
import 'package:otaku_reader/features/reader/screen_controls.dart';
import 'package:otaku_reader/features/reader/screen_wakelock.dart';
import 'package:otaku_reader/features/updates/controllers/updates_controller.dart';
import 'package:otaku_reader/data/repository/download_repository_impl.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';

/// Explicit dependency wiring.
///
/// AnymeX registers everything in one flat `Get.put` block whose *order* is
/// load-bearing, because its controllers call `Get.find` inside field
/// initializers — adding a controller in the wrong place throws at startup with
/// no indication why. Registering through a Bindings class and constructing
/// dependencies lazily keeps the graph explicit instead.
class AppBindings extends Bindings {
  AppBindings({required this.downloadRoot});

  /// Resolved in `main`, because it needs the platform documents directory and
  /// a stored preference — both of which are async, and `dependencies()` is not.
  final Directory downloadRoot;

  @override
  void dependencies() {
    Get.put<ThemeController>(ThemeController(), permanent: true);
    // One holder for the 18+ preference, observed by Home, Browse and
    // Settings. Each used to keep its own copy, so a write from one reached
    // none of the others.
    Get.put<NsfwPreference>(NsfwPreference(), permanent: true);

    // Eager and permanent, not lazy: every tab root renders it, its timer has
    // to be running before the first one is built, and it costs one string.
    Get.put<GreetingController>(GreetingController(), permanent: true);
    // Permanent, because the signed-in account is app-wide state and the
    // stored token is read once at startup rather than per screen.
    final anilistAuth = Get.put<AniListAuth>(AniListAuth(), permanent: true);
    // Not awaited: reading the keystore must not hold up the first frame, and
    // `isReady` is what every screen gates on — "not signed in" and "not
    // looked yet" are different states and are kept apart deliberately.
    unawaited(anilistAuth.restore());
    // Reads the user's own list rows. Stateless and never caches, so it is
    // safe to share one instance.
    Get.put<AniListListService>(
      AniListListService(anilistAuth),
      permanent: true,
    );

    // Repositories are registered against their *interfaces*, so nothing in the
    // feature layer can reach an implementation detail such as Isar or the
    // interpreter. They are permanent because the source repository caches live
    // runtimes: letting GetX dispose it would silently throw away parsed
    // extension scripts every time the last screen using one closed.
    Get.put<ExtensionRepository>(ExtensionRepositoryImpl(), permanent: true);
    Get.put<SourceRepository>(SourceRepositoryImpl(), permanent: true);
    Get.put<LibraryRepository>(LibraryRepositoryImpl(), permanent: true);
    Get.put<CategoryRepository>(CategoryRepositoryImpl(), permanent: true);
    Get.put<AniListRepository>(AniListRepositoryImpl(), permanent: true);
    // Permanent for the same reason as the source repository: it owns a live
    // queue, and a download must not stop because the screen that started it
    // was popped.
    Get.put<DownloadRepository>(
      DownloadRepositoryImpl(
        sources: Get.find<SourceRepository>(),
        library: Get.find<LibraryRepository>(),
        root: downloadRoot,
      ),
      permanent: true,
    );
    Get.put<AniListMetadataService>(
      AniListMetadataService(anilist: Get.find<AniListRepository>()),
      permanent: true,
    );
    // Registered rather than constructed inside the reader, so a test can put a
    // fake in its place -- the plugin behind it is a static platform channel
    // that a host VM can neither call nor watch.
    Get.put<ScreenWakelock>(const WakelockPlusScreen(), permanent: true);
    Get.put<ReaderScreenControls>(
      const PlatformReaderScreenControls(),
      permanent: true,
    );

    // lazyPut, so the catalogue is not read until the Browse tab is first
    // opened. The shell builds its tabs lazily for the same reason.
    Get.lazyPut<ExtensionsController>(
      () => ExtensionsController(
        nsfw: Get.find<NsfwPreference>(),
        extensions: Get.find<ExtensionRepository>(),
        sources: Get.find<SourceRepository>(),
      ),
      fenix: true,
    );
    Get.lazyPut<HomeController>(
      () => HomeController(
        nsfw: Get.find<NsfwPreference>(),
        anilist: Get.find<AniListRepository>(),
        library: Get.find<LibraryRepository>(),
      ),
      fenix: true,
    );
    Get.lazyPut<UpdatesController>(
      () => UpdatesController(
        library: Get.find<LibraryRepository>(),
        sources: Get.find<SourceRepository>(),
        network: const ConnectivityNetworkStatus(),
      ),
      fenix: true,
    );
    Get.lazyPut<LibraryController>(
      () => LibraryController(
        library: Get.find<LibraryRepository>(),
        sources: Get.find<SourceRepository>(),
        categories: Get.find<CategoryRepository>(),
      ),
      fenix: true,
    );
  }
}
