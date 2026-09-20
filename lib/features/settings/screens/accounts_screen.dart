import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/core/util/open_link.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';

/// Signing in to AniList.
///
/// Three states, kept distinct on purpose:
///
/// - **Not configured** — this build has no client id. A *setup instruction*,
///   not an error: a fresh clone is supposed to look like this, and offering a
///   sign-in button that cannot work is worse than not offering one.
/// - **Signed out** — sign in, by opening AniList and pasting the token back.
/// - **Signed in** — who, and a way out.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  AniListAuth get _auth => Get.find<AniListAuth>();

  @override
  Widget build(BuildContext context) {
    return ChromeScaffold.slivers(
      title: 'Accounts',
      slivers: [
        Obx(() {
          if (!_auth.isReady.value) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!_auth.isConfigured) return const _NotConfigured();
          final viewer = _auth.viewer.value;
          return viewer == null
              ? _SignedOut(auth: _auth)
              : _SignedIn(viewer: viewer, auth: _auth);
        }),
      ],
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverChromeSection(
      label: 'AniList',
      children: [
        const ChromeTile(
          icon: Iconsax.info_circle,
          title: 'Not set up in this build',
          subtitle:
              'AniList needs a client id, which identifies this build of the '
              'app to them. A fresh clone does not have one.',
          showChevron: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('To enable it:', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(
                '1. Create a client at anilist.co under Settings → Developer.\n'
                '2. Set its redirect URL to the pin page:\n'
                '   https://anilist.co/api/v2/oauth/pin\n'
                '3. Build with:\n'
                '   --dart-define=ANILIST_CLIENT_ID=<your id>',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    openLink(context, 'https://anilist.co/settings/developer'),
                icon: const Icon(Iconsax.export_3, size: 18),
                label: const Text('Open AniList developer settings'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.auth});

  final AniListAuth auth;

  @override
  Widget build(BuildContext context) {
    return SliverChromeSection(
      label: 'AniList',
      children: [
        const ChromeTile(
          icon: Iconsax.user,
          title: 'Not signed in',
          subtitle:
              'Sign in to sync reading progress and edit your list from here.',
          showChevron: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: () => _start(context),
            icon: const Icon(Iconsax.login, size: 18),
            label: const Text('Sign in to AniList'),
          ),
        ),
      ],
    );
  }

  Future<void> _start(BuildContext context) async {
    final opened = await openLink(context, auth.authorizeUrl.toString());
    if (!opened || !context.mounted) return;
    await _askForToken(context, auth);
  }
}

/// Collects the pasted token.
///
/// A separate step from opening the browser, and reachable again without
/// re-authorising: the user leaves the app to get the token and comes back,
/// and anything that only appears in the same breath as the browser opening
/// would be gone by then.
Future<void> _askForToken(BuildContext context, AniListAuth auth) async {
  final token = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(Chrome.cardRadius),
      ),
    ),
    builder: (context) => const _TokenSheet(),
  );
  if (token == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  final result = await auth.signIn(token);
  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (result) {
        SignInResult.ok => 'Signed in to AniList',
        // Not an error, and not a success either. The token works and the
        // session is live; it is the *saving* that failed, so the honest
        // thing is to say what will happen next rather than pick whichever
        // of the other two messages is less wrong.
        SignInResult.notPersisted =>
          'Signed in, but this device could not save the token. You will have '
              'to sign in again next time the app starts.',
        // Named as a rejection rather than "something went wrong": the
        // likeliest cause is a truncated paste, and saying so is the fix.
        SignInResult.rejected =>
          'AniList did not accept that token. Check the whole code was '
              'copied.',
      }),
      duration: result == SignInResult.ok
          ? const Duration(seconds: 4)
          : const Duration(seconds: 8),
    ),
  );
}

/// The sheet's body, and the owner of its text controller.
///
/// A `StatefulWidget` purely for that ownership. The obvious alternative —
/// build a `TextEditingController` beside `showModalBottomSheet` and dispose
/// it after the await — is **wrong, and fails loudly**: that future completes
/// when the sheet is *popped*, while its exit animation is still running and
/// the `TextField` is still in the tree. Disposing there throws "A
/// TextEditingController was used after being disposed" part-way through the
/// close.
///
/// Letting the sheet's own `State` hold it hands the lifetime to the
/// framework, which disposes once the route is actually gone — and covers the
/// dismissal path for free, which is the one a hand-rolled dispose after an
/// early return misses.
class _TokenSheet extends StatefulWidget {
  const _TokenSheet();

  @override
  State<_TokenSheet> createState() => _TokenSheetState();
}

class _TokenSheetState extends State<_TokenSheet> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Chrome.gutter,
        0,
        Chrome.gutter,
        MediaQuery.viewInsetsOf(context).bottom + Chrome.gutter,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste the token',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'AniList shows a long code after you authorise. Copy the whole '
            'thing and paste it here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Access token',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Chrome.leadingRadius),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Low, not top-right: the confirm on a sheet belongs where a thumb
          // already is.
          FilledButton(
            onPressed: () => Navigator.pop(context, _field.text),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.viewer, required this.auth});

  final AniListViewer viewer;
  final AniListAuth auth;

  @override
  Widget build(BuildContext context) {
    final avatar = viewer.avatarUrl;
    return SliverChromeSection(
      label: 'AniList',
      children: [
        ChromeTile(
          // `CachedNetworkImage`, as every other remote image in this app is:
          // a bare `NetworkImage` has no error branch, so an avatar that 404s
          // or a device that is offline throws out of the image resolver
          // instead of falling back to the icon — and it refetches on every
          // build of a screen the user opens to check one line of text.
          leading: ClipOval(
            child: SizedBox.square(
              dimension: Chrome.leadingSize,
              child: avatar == null
                  ? const _AvatarFallback()
                  : CachedNetworkImage(
                      imageUrl: avatar,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const _AvatarFallback(),
                      placeholder: (_, _) => const _AvatarFallback(),
                    ),
            ),
          ),
          title: viewer.name,
          subtitle: 'Scores shown as ${_formatLabel(viewer.scoreFormat)}',
          showChevron: false,
          trailing: IconButton(
            icon: const Icon(Iconsax.export_3, size: 18),
            tooltip: 'Open profile',
            onPressed: () =>
                openLink(context, 'https://anilist.co/user/${viewer.name}'),
          ),
        ),
        ChromeTile(
          icon: Iconsax.logout,
          title: 'Sign out',
          showChevron: false,
          onTap: () => _confirmSignOut(context),
        ),
      ],
    );
  }

  /// Read from the user's own AniList settings, not assumed.
  ///
  /// AniList stores every score as 0-100 whatever this says; showing a
  /// five-star user "8.0" would read as the wrong number rather than the
  /// wrong unit.
  static String _formatLabel(ScoreFormat format) => switch (format) {
    ScoreFormat.point100 => '100 points',
    ScoreFormat.point10Decimal => '10 points, with decimals',
    ScoreFormat.point10 => '10 points',
    ScoreFormat.point5 => 'stars',
    ScoreFormat.point3 => 'smileys',
  };

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of AniList?'),
        content: const Text(
          'Your library and reading progress stay on this device. Only the '
          'link to AniList is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    // `?? false`, because `showDialog` pops null for a barrier dismiss as well
    // as for Cancel and gives no way to tell them apart. Reading null as yes
    // would sign the user out for tapping next to the dialog.
    if (!(ok ?? false)) return;

    final forgotten = await auth.signOut();
    if (forgotten || !context.mounted) return;
    // The session ended, but the stored token did not, so it will sign them
    // back in at the next launch. Reporting "signed out" and then doing the
    // opposite is worse than an awkward sentence.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Signed out, but the saved token could not be removed. It may sign '
          'you back in when the app restarts.',
        ),
        duration: Duration(seconds: 8),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Icon(Iconsax.user, size: 20),
  );
}
