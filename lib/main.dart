import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart';
import 'package:otaku_reader/core/di/app_bindings.dart';
import 'package:otaku_reader/core/navigation/app_shell.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The database must be open before any controller is constructed: controllers
  // read persisted settings synchronously in their constructors and onInit.
  await AppDatabase.init();

  runApp(const OtakuReaderApp());
}

class OtakuReaderApp extends StatelessWidget {
  const OtakuReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Otaku Reader',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBindings(),
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
