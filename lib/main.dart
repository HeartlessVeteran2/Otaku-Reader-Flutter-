import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'package:otaku_reader/core/database/database.dart';
import 'package:otaku_reader/core/di/app_bindings.dart';
import 'package:otaku_reader/core/navigation/app_shell.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/repository/download_repository_impl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The database must be open before any controller is constructed: controllers
  // read persisted settings synchronously in their constructors and onInit.
  await AppDatabase.init();

  // Resolved here rather than lazily inside the repository: it needs the
  // platform's documents directory *and* a stored preference, so it is async,
  // and a download queue that cannot say where it writes until its first write
  // has nowhere to report a permission failure.
  final downloadRoot = await DownloadRepositoryImpl.resolveRoot(
    await getApplicationDocumentsDirectory(),
  );

  runApp(OtakuReaderApp(downloadRoot: downloadRoot));
}

class OtakuReaderApp extends StatelessWidget {
  const OtakuReaderApp({super.key, required this.downloadRoot});

  final Directory downloadRoot;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Otaku Reader',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBindings(downloadRoot: downloadRoot),
      home: const _ThemedApp(),
    );
  }
}

/// Rebuilds the themed subtree when the theme controller changes.
///
/// `GetMaterialApp` is constructed before `AppBindings` has run, so the theme
/// cannot be read at that point; applying it one level down keeps the
/// controller as the single source of truth and avoids a second theme cache.
class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    return Obx(
      () => MaterialApp(
        title: 'Otaku Reader',
        debugShowCheckedModeBanner: false,
        theme: theme.theme(Brightness.light),
        darkTheme: theme.theme(Brightness.dark),
        themeMode: theme.themeMode.value,
        home: const AppShell(),
      ),
    );
  }
}
