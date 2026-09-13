import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser, and says so when it cannot.
///
/// One helper rather than a `launchUrl` at each call site, because two rules
/// have to hold everywhere and both are easy to omit once:
///
/// * **Only `http` and `https`.** These URLs come from third parties — AniList
///   payloads and, indirectly, whatever a source put in them — and a scheme
///   such as `intent:` or `file:` hands an arbitrary app an argument the user
///   never saw. AniList's own mapper already filters, but a payload cached by
///   an older build never passed through today's mapper.
/// * **A failure must be visible.** `launchUrl` returns false on a device with
///   no browser for the scheme, and silently doing nothing on a tap reads as
///   the app being broken.
Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('That link cannot be opened')),
    );
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not open ${uri.host}')),
    );
  }
}
