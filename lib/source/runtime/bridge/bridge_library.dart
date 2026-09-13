/// The library URI that bridged types are registered under.
///
/// **This string is the extension-facing contract and must not be renamed to
/// match this package.** Every published Mangayomi source begins with
/// `import 'package:mangayomi/bridge_lib.dart';`, and the interpreter resolves
/// that import against the URI used at registration. Pointing it at
/// `package:otaku_reader/...` would leave every extension importing a library
/// that does not exist, and since `MProvider` is named in an `extends` clause,
/// each one would fail at class-definition time — the whole script, not one
/// method.
const String kBridgeLibraryUri = 'package:mangayomi/bridge_lib.dart';
