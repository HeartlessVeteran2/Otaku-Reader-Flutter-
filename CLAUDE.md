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

### Feature-layer rules

Decided while building the tabs, and each one has a wrong version that looks
identical from the outside.

- **`Chapter.dateFetch` is stamped only on a *refresh*.** It is null on every
  chapter of a manga's first fetch, and the Updates tab reads it. Stamping
  every new row instead puts a 3,864-chapter back catalogue into the tab the
  first time MangaRead.org's longest series is opened — which is worse than an
  empty tab, because it buries the two chapters that actually arrived.
- **History spans every stored entry; the Updates tab spans only favourites.**
  A chapter read from a source and never added is exactly what history is for,
  and refreshing everything ever opened is an unbounded crawl of sites that
  rate-limit.
- **`clearHistory` keeps `read` and `favorite`.** The user asked to forget a
  timeline, not to be handed back a library that thinks they have read nothing.
- **History's undo defers the delete rather than reinstating it.** Putting a
  timestamp back means inventing one. A second removal commits the first, and
  `undo()` returns false once a batch has committed — a snackbar outlives its
  window, so "too late" has to be an answer.
- **Anything that fans out over sources is bounded** (four at a time for global
  search, three for a library refresh). One request per installed source is 150
  connections with a Madara repo installed, which gets an IP rate-limited
  faster than it gets results.
- **A source that fails keeps its row.** Dropping it from a global search reads
  as "this manga is not on that source", which is a different and wrong answer;
  the same applies to a series that fails a library refresh.
- **Never name a controller method `refresh`.** `GetxController` already has
  one, from the notifier mixin, and GetX calls it internally to rebuild
  listeners. `UpdatesController.refreshLibrary` is so named because shadowing
  it would fire a library-wide network fetch every time the framework wanted a
  repaint.
- **Every external URL goes through `core/util/open_link.dart`**, which refuses
  anything but `http`/`https`. These URLs come from third-party payloads, and a
  scheme such as `intent:` or `file:` hands an arbitrary app an argument the
  user never saw. It also surfaces a failure: a tap that silently does nothing
  reads as the app being broken.
- **A download is all-or-nothing, and cancelling has two windows.** Pages land
  in a `.part` directory and are moved into place as one step, so there is no
  half-downloaded state a reader can open. Cancellation is checked *per page*
  and again *after the loop*, and those two checks do different jobs: the
  post-loop check is the correctness guard (it stops a cancel landing during
  the final fetch from renaming and reporting done), while the per-page check
  stops the **fetching**, so a cancelled download does not quietly pull every
  remaining page off the site before discarding it. A test asserting only the
  end state passes with the per-page check deleted.
- **`deleteChapter` awaits the in-flight run; `cancel` does not.** That
  asymmetry is deliberate — delete has a row to write and must not race the
  run writing `localPath` back — but it means `cancel` depends entirely on the
  run stopping *itself*, which is why the post-loop check exists.
- **A stale `localPath` is cleared where it is discovered, not where it is
  rendered.** The reader clears it on falling back. Checking existence at
  render time instead means a `stat` per visible row in a build method, on a
  chapter list that can be 3,864 long.
- **`resolveRoot` never throws for a *configured* path.** It runs before
  `runApp`, and the path is a stored preference — an unmounted SD card, a
  revoked permission. A throw there is a blank screen with no route to the
  setting that caused it, and clearing app data as the only recourse, which
  takes the library with it. It falls back to app documents and leaves the
  preference intact, so a card that comes back starts working again.
- **Read-modify-write on the KV tier needs a lock spanning *both* steps.**
  `ExtensionRepositoryImpl._withRepoLock` exists because two `removeRepo` calls
  interleaving — two quick taps — meant the second write was built from a list
  read before the first landed, and the repository the user deleted came back.

### The AniList account

- **The token lives in `flutter_secure_storage`, never in the KV tier.** That
  table is a plain Isar collection: a backup or anything that can read the
  database file carries the token off in clear text, and an AniList token can
  rewrite the user's whole list. AnymeX keeps its auth tokens in its KV table,
  and this is one of the things this app deliberately does not copy.
- **Sign-in is the PIN flow** (`response_type=token`, redirecting to
  `…/oauth/pin`), so the user pastes a token back. A real redirect URI needs a
  WebView to intercept it or an intent filter plus deep-link plumbing — two more
  Android plugins and a manifest entry, for a flow run approximately once. It
  also keeps the token out of a WebView this app would then own.
- **"No client id" is a first-class state, not a failure.** `ANILIST_CLIENT_ID`
  is a `String.fromEnvironment`, the developer registers it, and a fresh clone
  has none. Every surface renders a *setup instruction* there, never a sign-in
  button that fails on tap — the same shape as the Kotlin repo's gitignored
  `dev-repos.txt`. The Settings row has three states for the same reason:
  saying "Not signed in" on an unconfigured build contradicts the screen it
  opens.
- **`isReady` means "there is an answer to render", not "startup ran".** Every
  screen gates its spinner on it, so it is set by `restore()` whatever that
  finds **and** by a successful `signIn()`. Tying it to `restore` alone is
  invisible in the app — `AppBindings` always restores first — and an endless
  spinner anywhere else.
- **The score format is read from the user's own AniList settings.** AniList
  stores every score as 0-100 regardless; the format only says how to show it,
  and `POINT_10_DECIMAL` is AniList's own default. So hardcoding it looks
  correct for most users and shows a five-star user "8.0" for what their
  profile calls four stars — the wrong number, not merely the wrong unit. An
  unrecognised value falls back rather than throwing, because AniList adding an
  enum member must not stop a sign-in.
- **A 200 from GraphQL is not success.** AniList answers 200 with an `errors`
  array, and GraphQL's partial-failure shape carries `data` *and* `errors` in
  the same body. `query()` refuses that, because it is the one authenticated
  call everything else goes through and a half-failed mutation would otherwise
  report that a score saved when it did not.
- **Only a *refusal* deletes the stored token — never a failure to ask.** A
  check that comes back "no" means a dead token, a device with no signal,
  AniList being down, or a malformed query of our own, and those are not the
  same event. Dropping the token on any of them signs out a user whose token
  is fine, with the whole pin flow as the only way back; one wasted request
  per launch is far cheaper. So only HTTP 401, and a 400 whose body says
  "invalid token"/"unauthorized", count as a refusal. The match is narrow and
  errs toward *keeping* the token on purpose, because 400 is equally AniList's
  answer to a query this app got wrong.
- **Nothing in `AniListAuth` throws.** Every entry point returns its failure,
  because `restore()` is launched unawaited from `AppBindings` — an exception
  there has nobody to catch it and becomes an unhandled async error at
  startup. That covers the keystore (read, write *and* delete can each fail
  independently) and the payload, whose fields are checked rather than cast.
- **`signIn` has three outcomes and `signOut` has two**, because the keystore
  failing is not the same event as AniList refusing. "Accepted but not saved"
  is a live session that will not survive a restart; reporting it as a
  rejection sends the user to re-paste a token that works, and reporting it as
  success promises persistence that is not there. Likewise a sign-out whose
  delete failed ends the session but leaves the token to resurrect the account
  next launch, so it says so.

---

### The visual language: One UI over AnymeX's layout

Decided by the developer, and recorded because it is a *house style*, not a
preference to re-litigate per screen: **build the UI as a Samsung One UI
engineer would, over AnymeX's information architecture.** AnymeX decides what
is on a screen and in what order; One UI decides how it looks and where the
user's thumb goes.

What that means concretely, and what to check a new screen against:

- **A large collapsing header.** One UI's signature is a title that starts
  oversized in the top half and shrinks into the app bar as the content
  scrolls — `SliverAppBar.large`, expanded height around 150-170. It is not
  decoration: it pushes the first row of content into the lower half of a tall
  phone, which is the only part of the screen a thumb reaches.
- **Reach matters more than density.** Primary actions belong in the bottom
  third. A dialog's buttons, a sheet's confirm, a FAB — low, not top-right.
- **Rounded, grouped lists.** Related settings rows sit inside one rounded
  container (radius ~26) with the group's label above it in the accent colour,
  rather than as a flat divider-separated list. Cards and sheets share that
  radius; it is the most recognisable One UI tell after the header.
- **Soft surfaces, not shadows.** Elevation is expressed as a container
  colour step (`surfaceContainer*`), not a drop shadow.
- **Generous vertical rhythm.** One UI breathes: 20-24 between sections, not
  8-12.
- **Motion is short and eased**, never bouncy.

**Where the large header does *not* go, and why.** The pattern is not a
sweep. A collapsing title costs about 150px of the first screenful, and it
earns that only where the screen's own content is the point. Decided per
screen, after looking at each:

| Screen | Header? | Why |
|---|---|---|
| Home, Library, Updates, History | **yes** | Content-first lists. The header pushes the first row into thumb reach, which is what it is for. |
| Settings, More, About, Downloads | **yes** | Grouped lists, the canonical One UI shape. |
| Global search | **no** | Its app bar *title* is the search field. A large title above the field pushes the thing the user came to type into the middle of the screen. One UI's own search screens do the same: field in the bar, straight to results. |
| Source browse | **no** | 96px of search field and mode chips already. Adding 152px of title spends half a phone screen before the first cover, and the title is only the source's name — decoration next to controls the user actually presses. |
| Extensions | **no** | Same, plus 104px of search and a `TabBar` driving a `TabBarView`. A collapsing header over tab views needs `NestedScrollView`, which is a restructure with real regression risk bought for a visual change. |

A screen that keeps a compact app bar is not unconverted — it is converted
to the right answer. Do not "finish the job" by forcing the header onto
these three.

Two things from AnymeX to keep, because they are what the developer asked for:
the **carousel-of-covers home page** and the **AniList-rich details page**.
Two to drop: its glass/blur app bars (they fight the collapsing header) and
its habit of letting a service build its own widgets.

None of this is a reason to change behaviour. A screen that reads better and
does something different is a regression.

---

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
| Two PRs were too large for `sourcery-ai` to review **at all** — "larger than the review limit of 150,000 diff characters" | #1 was refused, the PR template gained a nudge toward smaller PRs, and #27 was then refused for the same reason. A PR nobody can review is not reviewed, however green. Land a working slice, not a phase. |
| Sourcery has a second limit, and a budget refusal is **not** durable | Besides the 150,000 diff characters per PR that refused #1 and #27, there is a **250,000 per 7 days** account budget. On #32 it reported that budget exhausted — check `skipped`, guide still generated, no findings pass — and then reviewed and approved the **very next push, six minutes later**. So: read the check state, not the message. `skipped` is not a pass and is easy to misread as one; but an exhausted-budget notice is not a reason to pause work or assume days of no coverage, because the observed behaviour contradicts its own wording. The mechanism is not understood, and guessing at one is how the wrong conclusion got written here in the first place. |
| A draft PR gets no bot review | CodeAnt skips drafts. Holding #27 as a draft "until the review settles" meant the review was never going to start, and its nine Major findings only surfaced once it was marked ready. Marking ready *is* the request for review. |
| The reader's webtoon resume never restored anything | The controller mapped the scroll onto a page index; the `ListView` was never scrolled back to it, so continuous-mode resume did nothing — while the commit message asserted "that is what makes resume mean anything in webtoon mode". `Chapter.currentOffset`/`maxOffset` existed for exactly this and went unused. Third instance of the same defect in one PR. |
| Evicting a cached source runtime **disposed** it | `dispose()` nulls the interpreter, so updating a source from the extensions screen killed any request a browse or reader screen had in flight on it. Eviction now drops the reference; only `evictAll` (teardown) disposes. Nothing leaks: the preference resolver is keyed by source id, so the replacement registers over the old entry. |
| A runtime's cache key covered only the script | `toMSource()` also hands `baseUrl`, `apiUrl` and `additionalParams` to the extension at construction, and `additionalParams` is what distinguishes one Madara site from the other 150 sharing that script. The fingerprint covers those fields now, and uses SHA-256 rather than `String.hashCode`. |
| #2 was merged 8 seconds after CodeAnt began reviewing it | Its status comment still reads "Reviewing your PR… / Finished: —". No findings were lost this time, but only by luck — and #2 existed *because* the same thing happened on #1. **Green CI is not the merge condition; a settled review is.** Before merging, check that every review bot has posted a finished status, not just that the gate passed. |
| The webtoon page index was arithmetic, not measurement | `pixels / maxScrollExtent × (pages - 1)` assumes every page is the same height. One tall spread shifts every boundary — and `_persist` treats "on the last page" as "finished", so an over-reported index marked a chapter read while the user was several pages from the end. Measure the laid-out children. |
| A failed reload reset the pagination cursor anyway | `_page = 1` was written *before* the fetch, and a failed refresh deliberately keeps the items on screen — so the list held page 2 while the cursor said page 1, and the next scroll appended a second copy. Commit a cursor only on success. |
| The AniList link chips shipped with `onOpen: (_) {}` | Live UI wired to nothing, which this file's own rule forbids. It analysed clean and looked finished. |
| Two `removeRepo` calls resurrected one another | Read-then-act with no lock across both steps. Making each step individually atomic changes nothing. |
| A cancel test asserted only the end state | It passed with the per-page cancellation check deleted, because the post-loop check cleans up either way — so the "stop fetching" half of cancel was uncovered. Deleting the guard is the only thing that showed it: the test now asserts the *fetch count*, not just the files. Assert what a guard uniquely prevents, not what any guard would leave behind. |
| A stored preference could throw out of `main` | `resolveRoot` created the configured download directory before `runApp`. An unmounted SD card meant the app never started, with no way to reach the setting and no recourse but clearing app data — which destroys the library. Anything in `main` that reads a user-supplied value needs a fallback, not an exception. |
| Reader tests pumped a fixed three microtasks | Adding a disk read and a row write to the load path made three too few, so `open()` returned a controller with no pages and three new tests failed on an empty list rather than on what they asserted. Wait on the condition (`while (c.isLoading.value)`), never on a turn count. |
| A controller built in `setUp` never fires its timers | `setUp` runs outside `testWidgets`' fake-async zone, so a `Timer` the controller starts there is not on the test clock and `tester.pump(anyDuration)` will not fire it. `LibraryController`'s 300ms change debounce never ran, and the grid looked broken when the reload simply never happened. Build a controller whose timers matter *inside* the test body. |
| Every controller in a suite had its own `LibraryRepositoryImpl` | They share the database but **not** the `changes` stream — `_changes` is a per-instance broadcast controller — so a write through one instance can never notify a listener on another. The harness was structurally unable to fail when the notification path broke, which is the path that exists because `didChangeDependencies` cannot fire on an `IndexedStack` reselection. One instance, shared. Found by `codeant-ai`, not by the suite. |
| `isReady` was set by `restore()` alone | Its own doc said "once the stored token has been read", and every screen gated its spinner on it meaning "do I have an answer". Signing in produced an answer and left the flag false, so the Accounts screen spun forever on a successful sign-in. Invisible in the app, where `AppBindings` always restores first — four widget tests failed at once and the flag, not the screen, was wrong. |
| A test named "a GraphQL error is a failure even though the status is 200" passed with the check deleted | Its body was `{"errors": […]}` with no `data`, which already fails on the absent `data`. The check only changes the answer for GraphQL's *partial* shape — a 200 carrying **both** — which is exactly the case a mutation half-failing produces. Deleting the guard is the only thing that showed it. |
| A sign-out test tapped Cancel and claimed to cover the barrier dismiss | Cancel pops an explicit `false`; the barrier pops **null**, and `ok ?? false` exists only for the null. Rewriting it as `ok != false` — signing the user out for tapping next to a dialog — left the Cancel test green. Whenever a guard turns on `?? `, the test has to produce the absent value, not the falsy one. |
| The AniList avatar was a bare `NetworkImage` | Every other remote image in this app is a `CachedNetworkImage` with an `errorWidget`. A bare one has no error branch, so a 404 or an offline device throws out of the image resolver, and it refetches on every build. Match the app's existing idiom before inventing a second one. |
| `flutter analyze` reported "No issues found" on a screen that could not lay out | Demonstrated rather than asserted this time: swapping one `SliverOneUiGroup` for its box-widget twin left analyze clean and failed two widget tests. The sixth instance, and the reason a rendered test per branch is not optional. |
| Four methods documented to *return* a failure could throw it instead | `signIn`, `signOut`, `restore` and `loadViewer` each let a keystore or payload failure escape as an exception. `restore` is unawaited from `AppBindings`, so its throw had nobody to catch it at all. Found by `codeant-ai`. The general check: when a method's doc says what it returns on failure, find every `await` inside it that can throw and decide what each one returns. |
| The obvious fix for "a dead token is retried forever" would have signed users out for being offline | `loadViewer` answered "no" for a rejection *and* for no network, AniList down, and our own bad query. Deleting the token on any failure — which is what the finding implied — costs a user with a perfectly good token their account, recoverable only through the whole pin flow. A review finding can be right about the defect and wrong about the remedy; verify the remedy separately, and prove it by applying the naive one and watching the right tests fail. |
| Disposing a sheet's `TextEditingController` after `await showModalBottomSheet` | That future completes when the sheet is **popped**, while its exit animation is still running and the `TextField` is still mounted — so the dispose throws "A TextEditingController was used after being disposed" part-way through the close. It is the fix that suggests itself, it reads as obviously correct, and a test that asserts only the end state never sees it because the throw happens mid-animation. Let the sheet's own `State` own the controller; the framework disposes it once the route is gone, and that covers the dismissal path too. |
| A row read `viewer` and ignored `isReady` | Written in the same commit as the rule saying those are different answers, and two files from the screen that honours it — so Settings said "Not signed in" during startup while the Accounts screen it opened said otherwise. Writing a rule down is not applying it; grep for the other readers of a flag whenever you add one. |

The general lesson, and the one that keeps recurring across both codebases:
**a comment describing the goal is not evidence the code achieves it.** After
writing a comment that asserts a property, re-read the code as if you had not
written it and find the path where the property does not hold.
