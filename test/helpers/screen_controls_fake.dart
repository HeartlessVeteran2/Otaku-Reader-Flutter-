import 'package:otaku_reader/features/reader/screen_controls.dart';

/// Records what the reader *asked the platform for*.
///
/// The point of the seam, and the reason it exists rather than a direct
/// `SystemChrome` call: two Settings switches shipped here writing keys
/// nothing read, and a round-trip test is exactly what would have passed the
/// whole time they were dead. So these tests assert the request, never the
/// stored value.
class FakeScreenControls implements ReaderScreenControls {
  FakeScreenControls({this.secureSucceeds = true});

  /// Whether [setSecure] reports the platform applied it.
  ///
  /// Settable because the *refusal* is a state the reader has to render — a
  /// build with no channel and a platform that said no both come back false,
  /// and a reader who believes screenshots are blocked when they are not is
  /// the failure this flag exists to reach.
  final bool secureSucceeds;

  final orientations = <ReaderOrientation>[];
  final immersive = <bool>[];
  final secure = <bool>[];

  @override
  Future<void> setOrientation(ReaderOrientation orientation) async =>
      orientations.add(orientation);

  @override
  Future<void> setImmersive(bool on) async => immersive.add(on);

  @override
  Future<bool> setSecure(bool on) async {
    secure.add(on);
    // A release always "succeeds": clearing a flag that was never set is not a
    // refusal, and reporting one would light the warning on the way out.
    return on ? secureSucceeds : true;
  }
}
