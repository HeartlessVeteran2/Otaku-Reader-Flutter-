import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/platform/network_status.dart';

/// Which connections count as free to crawl every installed source over.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(List<String> types) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'check') return types;
      return null;
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Wi-Fi and ethernet are unmetered', () async {
    for (final type in ['wifi', 'ethernet']) {
      answer([type]);
      expect(
        await const ConnectivityNetworkStatus().isUnmetered(),
        isTrue,
        reason: type,
      );
    }
  });

  test('mobile is metered', () async {
    answer(['mobile']);
    expect(await const ConnectivityNetworkStatus().isUnmetered(), isFalse);
  });

  test('**a VPN alone is metered**', () async {
    // A VPN is a tunnel, not a link: over mobile data it is exactly the case
    // the Wi-Fi-only switch exists to stop. `vpn` was in the unmetered set at
    // first, which made a scheduled library crawl over mobile data look free.
    // Found by `codeant-ai`.
    answer(['vpn']);
    expect(await const ConnectivityNetworkStatus().isUnmetered(), isFalse);
  });

  test('a VPN over Wi-Fi is unmetered, via the Wi-Fi entry', () async {
    // Which is why dropping `vpn` loses nothing: the list carries both, so the
    // real link is what decides.
    answer(['wifi', 'vpn']);
    expect(await const ConnectivityNetworkStatus().isUnmetered(), isTrue);
  });

  test('a platform failure answers unmetered', () async {
    // The deliberate direction. Treating "could not tell" as metered would
    // permanently stop automatic refreshes wherever the plugin misbehaves, and
    // the symptom is a feature that silently never runs.
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'boom'),
    );
    expect(await const ConnectivityNetworkStatus().isUnmetered(), isTrue);
  });
}
