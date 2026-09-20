import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/di/app_bindings.dart';
import 'package:otaku_reader/core/ui/greeting_controller.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';

import 'helpers/isar_test_env.dart';

/// What the app itself wires up.
///
/// This exists because `ProfileAvatar` and `GreetingText` deliberately render
/// their neutral state instead of throwing when their controller is missing,
/// so that a library-grid or extension-list test does not have to stand up an
/// AniList account to render the screen it is about.
///
/// That tolerance is only defensible while something proves the **app** does
/// register them. Without this file it would be the silent fallback this repo
/// rejected for `ChromeMetrics` — where a missing registration was
/// indistinguishable from a working app, because the fallback was also the
/// correct value. Here, absence is caught at the one place it can be.
void main() {
  late Directory downloads;
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('bindings', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  setUp(() {
    env!.clear();
    Get.reset();
    downloads = Directory.systemTemp.createTempSync('otaku-bindings');
    AppBindings(downloadRoot: downloads).dependencies();
  });

  tearDown(() {
    Get.reset();
    if (downloads.existsSync()) downloads.deleteSync(recursive: true);
  });

  test('the account the header renders is registered', () {
    // `ProfileAvatar` falls back to a blank tile without this, on every tab
    // root at once.
    expect(Get.isRegistered<AniListAuth>(), isTrue);
  });

  test('the greeting the header renders is registered', () {
    // `GreetingText` renders nothing without this, and the controller's
    // 15-minute timer would have no observer -- which is this project's
    // most-repeated defect wearing a clock.
    expect(Get.isRegistered<GreetingController>(), isTrue);
  });

  test('the greeting is eager, so its first phrase exists before a build', () {
    // Registered with `Get.put`, not `lazyPut`: the header reads `text.value`
    // on the first frame of the first tab root, and a lazily-created
    // controller would hand it an empty string until something else touched
    // it. Asserting the *value* rather than the registration is what tells
    // those two apart.
    expect(Get.find<GreetingController>().text.value, isNotEmpty);
  });
}
