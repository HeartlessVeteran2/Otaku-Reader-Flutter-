## What changed, and why

<!-- The reasoning matters more than the diff. What problem does this solve? -->

## How it was verified

<!-- Tick what you actually ran. CI runs all of these, but running them first
     saves a cycle. -->

- [ ] `flutter analyze` — clean
- [ ] `flutter test` — passing
- [ ] `dart format --set-exit-if-changed lib test tool`
- [ ] `dart run build_runner build` then `git diff --exit-code` (generated files current)
- [ ] `flutter build apk --debug`

## Source runtime

<!-- Delete this section if the change does not touch lib/source/. -->

- [ ] This PR does **not** touch the source runtime.
- [ ] It does, and `tool/source_sweep.dart` still holds the baseline
      (55/55 extensions evaluate, ≥6 complete `getPopular → getDetail → getPageList`).
      Result:

<!--
Two rules for anything under lib/source/:
  - Published extensions run UNMODIFIED. A source that fails is the runtime's
    bug, never the extension's. Never edit test/fixtures/.
  - Most of lib/source/ is ported byte-identically from Mangayomi. Diff against
    upstream before "fixing" something there — you may be changing behaviour
    that published extensions rely on.
-->

## Size

<!-- A reviewer (human or bot) can only review what fits. PR #1 was too large
     for one review bot to read at all. Smaller is better. -->
