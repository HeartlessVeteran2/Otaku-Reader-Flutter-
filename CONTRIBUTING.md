# Contributing

## Setup

**Flutter 3.47.4 exactly** (Dart 3.13.3) and JDK 21. The version pin is
load-bearing: `d4rt` needs Dart ≥ 3.9, and Mangayomi — whose extensions this app
runs — targets `sdk: ^3.13.1`. `CLAUDE.md` explains the rest of the toolchain.

```bash
flutter pub get
dart run build_runner build
```

## Before you open a PR

Run what CI runs. It is faster than a round trip:

```bash
dart run build_runner build && git diff --exit-code   # generated files current
dart format --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build apk --debug
```

**Keep PRs small.** The first PR here was large enough that one review bot
refused to read it at all.

## Rules for `lib/source/`

This directory runs third-party code, and three rules are non-negotiable.

1. **Extensions run unmodified.** A published extension that fails is the
   runtime's bug. Never edit an extension, and never edit
   `test/fixtures/madara_extension.dart.txt` — it is the real published
   `madara.dart`, and being unmodified is the whole point of it.
2. **Most of this directory is ported byte-identically from Mangayomi.** Diff
   against upstream before "fixing" anything. A finding there usually describes
   upstream behaviour that published extensions rely on, so changing it is a
   compatibility decision.
3. **Never rename `kBridgeLibraryUri`.** It is `package:mangayomi/bridge_lib.dart`
   because every published source imports that exact string.

Any change under `lib/source/` must hold the sweep baseline:

```bash
flutter test tool/source_sweep.dart
```

55/55 extensions evaluating and ≥6 completing the full chain. Note the sweep
needs live third-party sites, so it never gates a PR — run it yourself and put
the result in the PR description.

## Reporting a broken source

Check the site in a browser first. In this project's own measured sweep, *every*
hard failure was external. Use the "source is not working" issue template.

## Commits

Explain **why**, not what — the diff already says what. If you fixed something
subtle, say what the failure looked like, so the next person recognises it.
