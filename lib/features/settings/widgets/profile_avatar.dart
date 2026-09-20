import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/features/settings/screens/accounts_screen.dart';

/// The signed-in AniList face, at the head of a tab root.
///
/// Ported from AnymeX's `HeaderProfileAvatar`, which leads every one of its
/// tab roots with the account rather than with a title — the thing the
/// developer asked for by name when they said they wanted the home page
/// "interconnected with AniList".
///
/// **It lives in `features/`, not in `core/widgets/`, on purpose.** It resolves
/// `AniListAuth` through `Get.find`, and `chrome.dart` is deliberately free of
/// DI so `test/chrome_test.dart` can render every primitive with no
/// registrations at all. A chrome widget that needed a controller registered
/// before it could lay out would end that, so the coupling stays on this side
/// of the seam and `ChromeScaffold` only ever receives a finished `Widget`.
///
/// ### Four answers, not two
///
/// AnymeX has two states — logged in or not. This app has four, and collapsing
/// them is a mistake already recorded in `CLAUDE.md` twice (a Settings row that
/// read `viewer` and ignored `isReady`, and `isReady` being set by `restore()`
/// alone):
///
/// - **not ready** — startup has not answered yet. Claiming "signed out" here
///   is a sentence about a question nobody has asked.
/// - **not configured** — this build has no client id. A fresh clone looks like
///   this, and it is a setup instruction rather than a failure.
/// - **signed out** — an invitation.
/// - **signed in** — who.
///
/// Each carries its own tooltip, which is also how a test tells them apart:
/// they differ by a few pixels of icon otherwise.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.size = Chrome.leadingSize});

  final double size;

  @override
  Widget build(BuildContext context) {
    // A build with no `AniListAuth` registered renders the neutral tile rather
    // than throwing.
    //
    // This is **not** the silent fallback this repo rejected for
    // `ChromeMetrics`, and the difference is worth stating because the two
    // look identical in a diff. There, the fallback was 1.0 -- which is also
    // the correct production value, so a missing registration was
    // indistinguishable from a working app and could never be noticed. Here,
    // absence renders a permanently account-less header, which is visibly
    // wrong, **and** `app_bindings_test` asserts `AppBindings` registers
    // `AniListAuth`, so it cannot reach a device unnoticed.
    //
    // What it buys is that a library-grid or extension-list test does not have
    // to stand up an AniList account to render the screen it is actually
    // about. Making five tab roots unbuildable without an auth controller is
    // coupling those suites to something they do not test.
    if (!Get.isRegistered<AniListAuth>()) {
      return SizedBox.square(
        dimension: size,
        child: const ClipOval(child: _Placeholder()),
      );
    }
    return Obx(() {
      final auth = Get.find<AniListAuth>();
      final (tooltip, child) = switch ((
        auth.isReady.value,
        auth.isConfigured,
        auth.viewer.value,
      )) {
        (false, _, _) => ('Checking your account', _Placeholder(faded: true)),
        (_, false, _) => (
          'AniList is not set up in this build',
          const _Placeholder(),
        ),
        (_, _, null) => ('Sign in to AniList', const _Placeholder()),
        (_, _, final viewer?) => (viewer.name, _Face(url: viewer.avatarUrl)),
      };

      return Tooltip(
        message: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
          ),
          child: SizedBox.square(
            dimension: size,
            child: ClipOval(child: child),
          ),
        ),
      );
    });
  }
}

/// The signed-in face.
///
/// `CachedNetworkImage`, as every other remote image in this app is. A bare
/// `NetworkImage` has no error branch, so a 404 or an offline device throws
/// out of the image resolver — and this one renders on **every tab root**, so
/// it would refetch constantly. That exact swap is in `CLAUDE.md`'s mistakes
/// table for the Accounts screen's avatar; the fix is not to make it twice.
class _Face extends StatelessWidget {
  const _Face({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return const _Placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, _, _) => const _Placeholder(),
      placeholder: (_, _) => const _Placeholder(),
    );
  }
}

/// The house motif's tile, rounded off: `primary` at 12% behind a `primary`
/// glyph, which is what every other leading element in this app is.
class _Placeholder extends StatelessWidget {
  const _Placeholder({this.faded = false});

  /// Dimmed while startup has not answered. Deliberately not a spinner: a
  /// 36px slot cannot hold one legibly, and a spinner in the header on every
  /// cold start reads as the app being busy rather than as it being early.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: faded ? 0.4 : 1,
      child: ColoredBox(
        color: scheme.primary.withValues(alpha: 0.12),
        child: Icon(Iconsax.user, size: 18, color: scheme.primary),
      ),
    );
  }
}
