# CLAUDE.md — Otaku Reader (Flutter)

Read this before changing anything. It records the decisions a fresh session
cannot re-derive from the code, and the mistakes already made here.

---

## What this is

A manga/manhwa-first reader in Flutter, built on **AnymeX's tech stack** (GetX +
Isar), running the **Mangayomi extension ecosystem**, with **Komikku's**
library/browse UX as the target. It is a rewrite of the Kotlin
[Otaku-Reader](https://github.com/HeartlessVeteran2/Otaku-Reader), whose feature
set is the parity checklist — see `FEATURES.md`.

**Android first.** Code stays platform-agnostic; desktop is not a goal yet.

### Why the rewrite exists

The Kotlin app can only run the **JavaScript** half of Mangayomi's ecosystem,
which collapses to 18 distinct scripts, so it keeps a Tachiyomi APK backend
alive purely for catalogue size. Measured against the live index (363 entries):

| | index entries | distinct scripts | distinct sites |
|---|---|---|---|
| Dart (`sourceCodeLanguage: 0`) | 249 | **7** | **245** |
| JS (`sourceCodeLanguage: 1`) | 114 | 18 | 18 |

The 7 Dart scripts are site-parameterised multisrc templates — `madara.dart`
alone drives 151 sites. **Dart can interpret them; Kotlin cannot.** That is the
whole argument, and it removes any reason for a second backend.

---

## Toolchain — do not "upgrade" these casually

| Thing | Pin | Why |
|---|---|---|
| Flutter | **3.47.4** (Dart 3.13.3) | `d4rt` 0.2.4 pulls `analyzer >= 8.2.0`, which needs Dart >= 3.9. Mangayomi itself declares `sdk: ^3.13.1`. Matching the *extension ecosystem's* toolchain matters more than matching AnymeX's (which pins 3.32.8). |
| `isar_community_generator` | **Mangayomi's fork** (`kodjodevf/isar-community-generator`, ref `v3`) | The published generator pins a `source_gen` incompatible with analyzer 8. Symptom: `The method 'getInvocation' isn't defined for the type 'DartObjectImpl'`. |
| `isar_community` | `^3.3.2` (stable, not `3.3.0-dev.3`) | The generator fork requires the stable line. AnymeX pins the dev build; we cannot. |
| Android | `minSdk 24`, `compileSdk`/`targetSdk 36` | |

`android/build.gradle.kts` pins **every** Android subproject to the app's
`compileSdk`. Flutter plugins routinely lag the `compileSdk` their own
transitive dependencies demand, and one lagging plugin otherwise fails the whole
build. It is registered *before* `evaluationDependsOn(":app")`, which forces
subproject evaluation — a hook added after that arrives too late to configure
anything.

**Add dependencies per phase, as the code using them lands.** Declaring the
eventual set up front dragged in Android plugins pinned below the app's
`compileSdk` and failed the build for features that did not exist yet.

---

## The source runtime — the rules that matter most

Everything under `lib/source/` runs third-party code. Three rules, each learned
the hard way:

### 1. Extensions run unmodified

A published extension that fails is **the runtime's bug, never the extension's**.
Never edit an extension to make it work, and never edit
`test/fixtures/madara_extension.dart.txt` — that fixture is the real published
`madara.dart`, and its only value is being the genuine article. A review bot has
already filed three "bugs" against it; they are declined on principle.

### 2. Most of `lib/source/` is ported byte-identically from Mangayomi

Before "fixing" anything there, **diff it against upstream**. The only
intentional differences are the `kBridgeLibraryUri` constant and quote style;
`m_manga.dart` is byte-identical. A finding in a ported file describes *upstream
behaviour on the code paths that published extensions are written against* —
changing it is a compatibility decision, not a bug fix.

Any such change must be proven by re-running the sweep and holding the baseline
below. See the `upstream-behaviour` issues.

### 3. `kBridgeLibraryUri` is the extension-facing contract

`lib/source/runtime/bridge/bridge_library.dart` pins
`'package:mangayomi/bridge_lib.dart'`. **Never rename it to match this package.**
Every published source starts with that import, and the interpreter resolves it
against the URI used at registration. Renaming it breaks every extension at
once — and because `MProvider` is named in an `extends` clause, each one fails at
*class-definition* time, taking the whole script rather than one method.

For the same reason, **the bridge must be registered before the script is
evaluated**. The Kotlin app shipped a JS backend for months with `MProvider`
undefined and every source failing at evaluation, with nothing pointing at why.

### Other runtime invariants

- **Preferences: stored value wins, declared default is the fallback, read
  lazily and never seeded.** Sources ship their working mirror as a declared
  default. Upstream seeds a copy on first read, which freezes it — when the
  source later ships a new mirror because the old domain died, a user who never
  touched the setting keeps the dead one. `SourcePreferenceStore` deliberately
  never writes on a read; a test asserts this.
- **Links come back domain-stripped.** Sources emit paths and then hand them to
  `Uri.parse` expecting absolute URLs. Resolution happens once, in
  `DartSourceRuntime._absolute`, because whether a link is relative varies per
  site — MangaRead.org emits absolute links and works either way, Zinmanga does
  not. It cannot be left to call sites.
- **Date locale data must be loaded before the first parse.**
  `DateFormat(pattern, locale).parse` throws `LocaleDataException` otherwise,
  and upstream only initialises inside its *fallback* loop, so the first and
  likeliest parse always ran uninitialised. `MBridge._ensureDateFormatting`
  fixes this.
- **One HTTP client.** `MClient` is the single path, so there is one place to
  attach the cookie jar and the Cloudflare retry. The Kotlin app kept two stacks,
  only one carried cookies, and its bypass silently did nothing for JS sources,
  page images and OPDS.

### The measured baseline — this is what "working" means

Sweeping all 55 English/all-language Dart entries, chaining
`getPopular → getDetail → getPageList`:

```
evaluated:       55 / 55
popular listed:   8
detail+chapters:  6
full chain:       6
```

Full chain: MangaRead.org (12 → 3864 chapters → 13 pages), Raven Scans (95 → 218
→ 21), Mangasushi, MangaEffect, KSGroupScans, LHTranslation.

Every other failure is external — dead or parked domains, 301s to moved sites,
sandbox proxy 502s, TLS refusals. **Check the site with `curl` before suspecting
this code.**

Re-run with `flutter test tool/source_sweep.dart` (optionally
`--dart-define=SOURCE=madara --dart-define=LIMIT=8`). It lives in `tool/`, not
`test/`, so `flutter test` never collects it: it needs live third-party sites and
must never gate a PR.

---

## Architecture

```
UI (widgets, Obx)
  └─ GetxController (Rx state)
       └─ Repository (interface, pure Dart)
            └─ Isar collections / SourceMethods / tracker HTTP
```

Repositories stay interfaces so GetX is not load-bearing in the domain layer.

### Persistence

- **`AppDatabaseSchemas.all`** is the single schema list. A collection that is
  `@collection`-annotated and generated but missing from it compiles, analyses
  clean, and throws the first time anything touches it. `Source` shipped that
  way. `test/database_schema_test.dart` opens *this exact list* and round-trips a
  row per collection — do not let a test open a hand-picked subset instead.
- **`KvHelper` + `data_keys/keys.dart`** are the key/value tier. Every key is an
  enum member with `.get<T>()`/`.set<T>()` grafted on by extension, so no key is
  ever a string literal. Values are stored as `{'val': ...}` so `null`, `bool`,
  `num`, `String`, `List` and `Map` all round-trip through one nullable column.
  `DynamicKeys` namespaces per-media values by id.
- **A `get<T>()` with no default and a non-nullable `T` throws when the key is
  absent** — it ends in `null as T`. Read with a nullable `T` whenever "absent"
  is a state you need to tell apart from a stored value, which it usually is:
  for `SourceKeys.repoUrls`, absent means "seed the default repo" and empty means
  "the user deleted every repo", and conflating them resurrects a repo they
  removed on every launch.
- **A list's element type comes from the data, not from `T`.** `jsonDecode`
  erases it to `List<dynamic>`. `KvHelper` used to cast *every* list to
  `List<String>`, which succeeds at the cast and then throws on first element
  access for anything else — so a `List<Map>` round-tripped in name only. The
  suite covered exactly one list case, `List<String>`, which is the one that
  worked.
- **`MangaEntry.sourceId` is the source's *string* id, stored verbatim.** The
  Kotlin app keyed rows by `sourceStringId.hashCode()` and calls the resulting
  one-way mapping its highest-impact bug ever. Isar needs no integer key, so that
  class of bug is designed out. Keep it that way.
- Secrets go to `flutter_secure_storage`, never the KV tier.

### Deliberate departures from AnymeX

AnymeX is the reference, not the gospel. Do not carry these over:

1. **Its DI is a flat `Get.put` block with a load-bearing order**, because
   controllers call `Get.find` in field initializers. Use explicit `Bindings`.
2. **It has no router** — `Navigator.push(Get.context!, …)` via thunks.
3. **`TlsSettings(verifyCertificates: false)`.** Never.
4. **Auth tokens in plaintext** in its KV table.
5. **Hive is declared and unused**; so are `background_downloader` and
   `jxl_coder`.
6. **`BaseService` returns `RxList<Widget>`** — services build their own home
   pages. Return data; let one screen render it.

---

## Verification

Run all of these before pushing; CI runs the same set.

```
flutter pub get
dart run build_runner build && git diff --exit-code
dart format --set-exit-if-changed lib test tool
flutter analyze
dart run tool/fetch_isar_core.dart
flutter test
flutter build apk --debug
```

**`dart run tool/fetch_isar_core.dart` is not optional, and not a cache warmer.**
Isar's native library is downloaded rather than vendored, and
`TestWidgetsFlutterBinding` replaces `HttpClient` with one that answers every
request `400` and makes no network call — so a **widget** suite can never fetch
it, and fails with the opaque `Could not download IsarCore library:` and an empty
reason phrase. Whichever Isar-using suite runs first decides whether the run
passes. Fetching it from a plain Dart VM first removes the download from the test
run entirely. `IsarTestEnv` and the script agree on one pinned path
(`.dart_tool/otaku/`), because Isar otherwise derives the path from
`Platform.script` — a per-suite generated entrypoint under `flutter test`, so
suites disagree about where the library even is.

Two things only a **release** build shows: the merged manifest (the `INTERNET`
permission lives in `src/main`, not `src/debug` — a debug-only check cannot see
it) and R8/shrinking behaviour.

---

## Mistakes already made here

Kept because they repeat.

| What | What actually happened |
|---|---|
| `Source` was `@collection`-annotated and generated, but never added to the schema list | Every test opened a subset, so nothing caught it. Fixed + guarded by `database_schema_test.dart`. |
| `INTERNET` was only in the debug manifest | Every local check was a debug build. A release build would have had no network at all. |
| `int status = 5` as a default | `Status` index 5 is `publishingFinished`, so every new entry claimed to be finished. Use the enum, not a literal. |
| A dead FFI helper allocated N *bytes* for N *pointers* | Unused, so it was deleted rather than fixed — along with the `ffi` dependency it dragged in. |
| The plan claimed AnymeX's manga details page renders news/adaptation/prediction | It does not: `buildExtrasSection` is guarded by `if (controller.isAnime)`, and `manga_stats.dart` is orphaned with zero imports. Verify what actually renders before promising parity with it. |
| CI's first red was diagnosed as a cold-cache race between suites downloading `libisar.so`, and "fixed" with `flutter test -j 1` | Wrong cause, and the "verified locally" claim behind it was worthless — the file was already on disk from an earlier run. Serialising just moved the failure to whichever Isar suite ran first, which was the **widget** suite, which can never download anything. Reproduce a CI failure locally *from the same starting state* before believing a fix. |
| `KvHelper` cast every stored list to `List<String>` | It succeeds at the cast and throws on first element access, so a `List<Map>` looked fine until something read it. The test covered only `List<String>` — the single case that worked. A green test that exercises only the working shape is how this survives. |
| #2 was merged 8 seconds after CodeAnt began reviewing it | Its status comment still reads "Reviewing your PR… / Finished: —". No findings were lost this time, but only by luck — and #2 existed *because* the same thing happened on #1. **Green CI is not the merge condition; a settled review is.** Before merging, check that every review bot has posted a finished status, not just that the gate passed. |

The general lesson, and the one that keeps recurring across both codebases:
**a comment describing the goal is not evidence the code achieves it.** After
writing a comment that asserts a property, re-read the code as if you had not
written it and find the path where the property does not hold.
