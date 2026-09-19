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

### Why the rewrite exists, and what that argument left out

The Kotlin app can only run the **JavaScript** half of Mangayomi's ecosystem,
which collapses to 18 distinct scripts, so it keeps a Tachiyomi APK backend
alive purely for catalogue size. Measured against the live index (363 entries,
**all of them manga** — there is no anime half):

| | index entries | distinct scripts | distinct sites |
|---|---|---|---|
| Dart (`sourceCodeLanguage: 0`) | 249 | **7** | **245** |
| JS (`sourceCodeLanguage: 1`) | 114 | 18 | 18 |

The 7 Dart scripts are site-parameterised multisrc templates — `madara.dart`
alone drives 151 sites. **Dart can interpret them; Kotlin cannot.** That part is
true and still is.

**What it left out is the price.** "No second backend" was stated as a pure win.
It is a trade, and nobody wrote down the other side: the Kotlin app's APK
backend reaches the Tachiyomi/Mihon catalogue, which is **1,396 extension
packages** (2,387 sources, 566 of them English or all-language) against this
ecosystem's ceiling of **263 distinct sites**, of which we run 245. So the
rewrite bought architectural simplicity by giving up roughly **6x the
catalogue, and 10x the English-facing sources**.

For a manga reader the catalogue is the product, so that trade is the wrong way
round — and it is not something more work in this codebase closes, because the
ceiling is the ecosystem's, not ours.

**Decided 2026-09-19: adopt AnymeX's extension bridge and stop maintaining a
parallel source runtime.** See "The extension bridge" below.

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

## The extension bridge — the decision that supersedes phase 1

**`anymex_extension_runtime_bridge`** (`RyanYuuki/AnymeXExtensionRuntimeBridge`)
is a Flutter **plugin**, Dart *and* Android, that AnymeX uses for its whole
source layer. Everything under `lib/source/` here is a parallel implementation
of the Mangayomi part of it, ported from the same upstream. Phase 1 built it
without checking whether the reference app already had one.

### What it is

`Extension` is the seam, implemented once per backend — Mangayomi, Aniyomi,
Kotatsu, CloudStream, Legado, LnReader, Sora:

```dart
Future<void> addRepo(String repoUrl, ItemType type);   // per backend, per type
Future<void> removeRepo(String repoUrl, ItemType type);
Future<void> installSource / uninstallSource / updateSource(Source);
Rx<List<Source>> getInstalledRx / getAvailableRx(ItemType);
Rx<List<Repo>>   getReposRx(ItemType);
bool get requiresPlugin;                 // Kotatsu: needs a plugin.jar
Map<String, ExtensionSetting>? settings; // per-backend settings
SourceMethods createSourceMethods(Source source);
```

`SourceMethods` is the call surface the reader and browse sit on. The verb
*names* rhyme with this app's; the **contracts do not**, and the difference is
an adapter rather than a rename. Diffed, not assumed — the first version of
this paragraph claimed "the same verbs this app already uses", which
`codeant-ai` caught:

| `lib/source/source_methods.dart` | the bridge's `SourceMethods` |
|---|---|
| `getSourcePreferences()` → `List`, **sync** | `getPreference()` → `Future<List>`, **async** |
| `getFilterList()` → `FilterList`, **sync** | `getFilterList()` → `Future<List<dynamic>>` |
| `getDetail(String url)` | `getDetail(DMedia media)` |
| `getPageList(String url)` | `getPageList(DEpisode episode)` |
| `MPages` / `MManga` / `FilterList` | `Pages` / `DMedia` / `List<dynamic>` |
| `getHeaders()`, `dispose()` | — |
| — | `setPreference`, `cancelRequest`, `getVideoList`, `getVideoListStream`, `getNovelContent`, `stopHttpServer` |
| — | a `SourceParams?` named argument on every call |

`getPopular`, `getLatestUpdates` and `search` line up on name and shape, and
that is the extent of it. **So slice 1 is a model-translation layer**
(`MManga` ↔ `DMedia`, `MPages` ↔ `Pages`, `FilterList` ↔ `List<dynamic>`) plus
a sync-to-async shift on preferences and filters — not the rename the first
draft implied. The anime and novel members (`getVideoList`, `getNovelContent`)
are surface this app never calls and can throw `UnimplementedError`.

`Repo` carries `{url, name, iconUrl, extensions, managerId}` — note
`managerId`, the field this app's own repo model lacks, because ours only ever
had one backend.

### Repos are yours to add, per backend

This is the part that matters and the part a survey misses:

- **Aniyomi** takes any Tachiyomi/Mihon repo URL. `_parseExtensions` sniffs the
  gzip magic, then branches on the first byte: JSON for the old flat
  `index.min.json`, otherwise **protobuf** through a hand-rolled `PbDecoder`.
  Media type comes from an `Aniyomi: `/`Tachiyomi: ` name prefix, falling back
  to `.anime.`/`.manga.` in the package name; multi-language packages collapse
  to one row carrying `langs`.
- **Kotatsu**'s repo URL *is* a `plugin.jar`: adding one downloads it and
  clears the parser cache. `requiresPlugin => true`.
- **Mangayomi** reads the same `index.json` this app already reads.

**Keiyoushi's `index.min.json` is now a two-entry "Outdated App" stub.** The
live index is `.../keiyoushi/extensions/repo/index.pb` — gzipped, ~706 KB
decompressed, **1,396 packages** — and the protobuf branch is exactly what
reads it. A count taken from the repo's nested `index.json` is *not* reachable
by this parser, which returns `const []` for any JSON that is not a list.

### Why it could not be a dependency, and why it now can

The bridge pins `d4rt 0.1.7` and `isar_community 3.3.0-dev.3` **exactly**.
`d4rt <0.2.0` wants `analyzer ^7.4.5`; Mangayomi's `isar_community_generator`
fork wants `analyzer ^8.4.0`. No `dependency_overrides` combination resolves
that — four attempts, all recorded.

The resolution is that the conflict only exists while this app carries **its
own** `d4rt ^0.2.4`. Drop that with `lib/source/`, take the bridge's runtime,
and move Isar to AnymeX's pins, and it resolves: 160 dependencies, and the
seam analyses clean from this app's own code. That is AnymeX's configuration,
which is the point — one toolchain instead of two.

| | before | after |
|---|---|---|
| source layer | `lib/source/` (4,361 lines) | the bridge plugin |
| `d4rt` | `^0.2.4` | `0.1.7` (the bridge's) |
| analyzer | 8 | 7 |
| Isar | `^3.3.2` + Mangayomi's generator fork | `3.3.0-dev.3` + the published generator |

**So the toolchain table above is superseded by this row** — the Flutter pin,
the generator fork and the `isar_community` stable-line pin all existed to
serve a `d4rt` this app no longer owns.

### The order to do it in

Mangayomi through the bridge is **pure Dart** — no native dependency — so it
proves the seam on its own, and the model translation above is most of that
slice's real work. Aniyomi and Kotatsu need the Android side
(`MethodChannel('aniyomiExtensionBridge')`, a runtime host APK, a `plugin.jar`),
which is where the 1,396 packages come from and where the real integration risk
is. Do them in that order, and do not delete `lib/source/` until the first one
browses and reads end to end.

### What this does not change

`lib/source/`'s **rules** were right and the deferred `upstream-behaviour`
issues still describe real upstream behaviour — the bridge ports the same files
from the same place. Nothing here says that work was wrong; it says it was
already done elsewhere, and that checking first is cheaper than being right
twice.

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
- **...but only when there is an `await` between the read and the write.**
  That is the rule's precondition, and it is easy to apply the rule without
  checking it. `_removeRepo` awaits `getRepos()` mid-sequence, so it genuinely
  needs the lock. The repo-health writes do not: `KvHelper.get` is
  `findFirstSync` and `set` is `writeTxnSync`, so read-modify-write runs in one
  turn of the event loop and nothing can interleave on Dart's single thread.
  They are deliberately **`void`, not `Future`** — a lock there would guard
  nothing while reading as though concurrency had been handled, and a `Future`
  return type invites an `await` to be added inside, at which point the
  atomicity vanishes with no signature change to notice.
- **Per-repo health is recorded for every exit of `refresh`.** It is a thin
  wrapper around `_refresh` for exactly that reason: the inner method returns
  early in three places, and an unrecorded *failure* is the one case the
  feature exists for. A refresh that fails deliberately leaves the known
  sources in place — a flaky network must not empty the extension list — which
  also means a dead repo is indistinguishable from a healthy one until you
  notice it never gains anything.
- **"Never checked" is a third state, not a failure.** A repo added before the
  record existed, or one whose refresh has never run, carries none — and that
  is something the user can act on, where "failed" is a claim about a request
  that was never made.

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
  finds **and** by `signIn()` whatever it answers — a rejection is an answer
  too. It is set in a `finally` rather than per path, because the invariant
  otherwise survives only thanks to a gate in a *different file* (the sign-in
  button renders only once `isReady` is true), and this same flag has already
  been wrong once for leaning on something invisible like that.
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
- **The list lookup is four answers, not a nullable row.** Signed out,
  unreachable, not-on-your-list and on-your-list. They were deliberately
  collapsed into one nullable entry while the row was read-only, because all
  four rendered the same — nothing. Editing ended that: "not on your list" is
  an invitation to add it, and offering that while AniList is *unreachable*
  offers an action about to fail. When a state stops rendering the same as its
  neighbours, the type that conflated them has to change with it.
- **`SaveMediaListEntry` creates the row when there is none**, so adding an
  untracked manga and editing a tracked one are the same call and the same
  sheet — there is no separate "add" path to keep in step.
- **Only the fields the user actually changed are sent.** AniList writes
  exactly what it is given, so passing a field they never touched writes back
  a value read minutes ago and undoes progress made on another device in
  between. Null means "leave it alone" — which is why `0` must still be sent:
  stepping progress back to the start is a real edit, and treating falsy as
  absent would make it silently do nothing.
- **"Busy" is not "refused".** `saveAniList` returns three outcomes for the
  same reason `signIn` does: a write dropped by the in-flight guard was never
  offered to AniList, so reporting it as "AniList did not save that" is a
  sentence about a server that was never asked. The row is also untappable
  while a write is in flight — with a spinner, because a tap target that
  silently stops responding reads as broken rather than busy.
- **A write publishes only if the page is still about the same media.**
  Unlinking or re-linking while a save is in flight leaves the response
  describing a series the page no longer claims to be, and restoring a row the
  user just removed is worse than dropping a display update. The guard is the
  **media id**, deliberately not the `_generation` counter the load path uses:
  `unlinkAniList` does not bump the generation, so a generation compare —
  which is the fix that suggests itself — misses the exact case that matters.
- **The saved row comes from the response, not the request.** AniList
  normalises — completing a series moves progress to the chapter count — so
  echoing back what was asked for shows a number the server does not hold.
- **The user's own list row is never cached; the public record is.**
  `AniListMetadataService` serves the series and caches it per entry on a
  7-day TTL. `AniListListService` serves the reader's own row — status,
  progress, score — and fetches it live every time, because progress changes
  whenever they read a chapter on another device. A cached number claiming
  they are on chapter 12 after they read 20 elsewhere is worse than no number.
- **A score of 0 is *unscored*, not a score of zero.** AniList stores no
  "unset" — every format bottoms out at 0 — so taking the number at face value
  stamps a rating of zero on every entry the user never rated, which is most
  of them. Both the model and the rendered row drop it.
- **The score's format travels with the score.** `AniListListResult` carries
  the `ScoreFormat` AniList reported in the *same response* as the row, and
  the editor uses that rather than the cached viewer's. The cache is written
  once at sign-in and the format is a server-side setting the user can change
  from another device — so reading in one scale and writing in another turns
  an 85/100 into a five-star 85. One extra field on a request already being
  made closes it. What is left is a seconds-wide window between the lookup and
  the save, which only `scoreRaw` could close, and that would mean inventing
  AniList's undocumented POINT_3 mapping.
- **`score` is sent, never `scoreRaw`.** The mutation takes both. `scoreRaw`
  is always 0-100 and looks like the tidier choice, but converting a POINT_3
  smiley to it means inventing a mapping AniList does not publish — so the one
  format where the arithmetic is a guess is the one where a wrong guess is
  most visible. Handing back the units the row was read in needs no arithmetic.
- **`score` is requested with an explicit `format:`.** The schema is
  `score(format: ScoreFormat)`, verified by introspecting the live endpoint.
  Leaving it to AniList's default is what shows a five-star user a ten-point
  number their own profile never displays.
- **Reporting a finished chapter is serialised, and the lock spans both
  steps.** `AniListProgressSync` asks AniList what it holds and then writes a
  bigger number, and the reader fires it *unawaited* from a page turn — so
  finishing two chapters a tap apart starts two overlapping reports. Both read
  the same held value, both decide to write, and the writes then race: chapter
  2's can land first and chapter 1's second, leaving AniList on 1. The
  never-lower rule cannot catch it, because each call was correct about the
  value it read. Found by `codeant-ai`.
- **`CURRENT` is "Reading", not "Current".** `MediaListStatus` is shared with
  anime, where the same value means "Watching"; `REPEATING` likewise. An
  unrecognised status renders the raw value prettified rather than falling
  back to a known one — AniList adding a status must leave the row unlabelled,
  never claim the user is reading something they are not.
- **`signIn` has three outcomes and `signOut` has two**, because the keystore
  failing is not the same event as AniList refusing. "Accepted but not saved"
  is a live session that will not survive a restart; reporting it as a
  rejection sends the user to re-paste a token that works, and reporting it as
  success promises persistence that is not there. Likewise a sign-out whose
  delete failed ends the session but leaves the token to resurrect the account
  next launch, so it says so.

---

### The visual language: AnymeX's chrome

**Decided by the developer, twice, and the second decision reversed the first.**
Recorded in full because a section that only states the current rule reads as
though the alternative was never considered, and the next session re-litigates
it.

**What it was.** Phase 7 built the UI "as a Samsung One UI engineer would" over
AnymeX's information architecture: `SliverAppBar.large` collapsing headers on
eight screens, a per-screen table deciding where they went, Material `TabBar`s,
`ListTile` rows, and an explicit instruction to *drop* AnymeX's glass/blur app
bars because they fight a collapsing header.

**What it is now.** The developer: *"I prefer AnymeX kind of layout over the
bars or whatever from komikku style"*, and, asked how far that goes, chose
**AnymeX chrome everywhere** over keeping the collapsing headers. So the
headers go, and the blur comes back — that instruction to drop it existed only
because of the header it fought, and the reason left with the header.

What survives from One UI, because it never conflicted: reach matters more than
density (primary actions in the bottom third), elevation as a surface colour
step rather than a drop shadow, generous vertical rhythm, and short eased
motion. AnymeX agrees with all four.

#### The four shapes

Ported from `/home/user/AnymeX-HV`, which is checked out in every session.

- **The header is two floating pills, not a bar.** A title pill on the left, an
  actions pill on the right, and the content scrolls *under* both. Each pill is
  a `ClipRRect` over a `BackdropFilter(blur 16)` filled with
  `surfaceContainer` at 55% alpha, a 0.5px `onSurface`-at-8% hairline border and
  a soft shadow, at radius 30. A full-width opaque bar is the Komikku shape and
  is what the developer asked to move away from.
- **Search toggles in place.** The header swaps its split row for a search row
  through an `AnimatedSwitcher` (300ms, `easeOutCubic`) rather than stacking a
  permanent field under the title. This is what buys back the height the
  collapsing header used to spend.
- **Tabs are a segmented pill, and cannot overflow.** An `AnimatedAlign` moves a
  `FractionallySizedBox(widthFactor: 1 / total)` behind a `Row` of `Expanded`
  tabs whose labels are `Flexible` and ellipsised. Every tab is a fraction of
  the available width *by construction* — which is why this replaced Material's
  `TabBar` rather than patching it. See the mistakes table: that `TabBar`
  overflowed at 320, **360 and 384**, on a bug class this shape does not have.
- **Rows are cards, through one container primitive.** Rounded, optionally
  bordered, optionally carrying a primary-tinted glow, always clipped. The
  leading element is the house motif: a 36x36 rounded-10 tile filled
  `primary` at 12% with a 20px `primary` icon. A tappable row ends in a
  `chevron_right_rounded` at `onSurface` 35%.

#### Two things to carry that are easy to miss

- **Radius, glow and blur are scaled by user multipliers.** AnymeX runs every
  radius through `multiplyRadius()` and every glow through `multiplyGlow()`, so
  the whole app's roundness is a setting. Worth adopting rather than hardcoding
  numbers in thirty widgets.
- **A choice belongs inside its row.** AnymeX's tile embeds a segmented
  selector, so a setting changes without leaving the row. This app opens radio
  dialogs (`_pick<T>`), which is the pattern being moved away from.
- **The header's height is *measured*, not computed.** The body fills the
  screen and the pills float over it, so a list has to start below them and
  then scroll under them — which means something has to say how tall the
  header is. AnymeX hardcodes 64, or 80 with a subtitle. Every arithmetic
  version of that written here was wrong about something it could not see: a
  caller passing a Material `IconButton` at its 48px minimum, the search row's
  `TextField` metrics at a large system font, the line height the engine
  rounds a scaled font to. `ChromeScaffold` keeps the arithmetic as a
  first-frame estimate and uses the header's real height from the next frame
  on. Removing the measurement fails exactly one test — searching at a doubled
  font size — which is the point: that is the state the estimate cannot reach.

#### Still from AnymeX, unchanged by any of this

The **carousel-of-covers home page** and the **AniList-rich details page**, both
of which the developer asked for by name. And still not carried over: its habit
of letting a service build its own widgets — return data, let one screen render
it.

None of this is a reason to change behaviour. A screen that reads better and
does something different is a regression.

---

### The brand palette, and why the theme is composed from three seeds

The logo is the app's colour scheme, by the developer's instruction. The three
inks are **measured** off the artwork (quantised, modal colour per hue family),
not picked by eye, and `tool/generate_launcher_icons.py` reads the same file for
the launcher icon so the icon and the UI cannot drift apart:

| role | ink | where it is in the mark |
|---|---|---|
| primary | `#FA60BE` | the petals — 94% saturation, what the mark is recognised by |
| secondary | `#313575` | the wordmark and the kanji strokes |
| tertiary | `#E17559` | the accents between the petals |
| — | `#0A0A0B` | the ground, used by the icon and the launch window only |

- **`ColorScheme.fromSeed`'s `secondary:`/`tertiary:` overrides are a trap.**
  They replace the **finished role colour**, not the palette behind it — so a
  navy `secondary` keeps an `onSecondary` derived from the pink. Measured over
  all 18 brightness × variant combinations, that version bottoms out at a
  contrast ratio of **1.14** (dark `monochrome`) and **1.30** — and the 1.30 is
  light `fidelity`, *the variant a fresh install starts on*. It would have
  shipped unreadable secondary text on day one, on the default setting.
- **So each ink seeds its own scheme and its `primary` family is lifted whole**
  into the slot it belongs in (`brandColorScheme`). Every on-colour was
  generated by Flutter's own engine against the colour it sits on, so contrast
  is guaranteed by construction rather than hoped for — the lifted version never
  drops below 4.54 — and the app keeps tracking whatever that engine does next.
  Lifting a *partial* family is the same bug in miniature: dropping just
  `onSecondaryContainer` breaks two contrast cases.
- **The three inks apply only when the brand seed is in force.** A user who
  picks green, or a cover tint that comes back green, asked for green; handing
  them green with the logo's navy and coral stapled on is not their colour. The
  seed and the "is this ours?" flag are returned together from one place
  (`_resolvedSeed`) because they are one decision — computing the flag
  separately is how they drift.
- **The default variant is `fidelity`, not Flutter's `tonalSpot`.** `tonalSpot`
  caps chroma and renders the petal pink as `#874B6C`, a 28%-saturation mauve
  that nothing in the logo is printed in. `fidelity` gives `#AD1B7E` /
  `#1A1E5E` / `#9D422A`: the mark's own inks. Every variant stays selectable;
  this only decides where a fresh install starts. It is named through the enum,
  never stored as the literal `1` — see the `int status = 5` row below.
- **The launch window has a light twin and a dark twin.** Flutter's template
  ships plain white for both, which is a white flash in front of a dark app on
  every cold start. Making it *black* for both only moves the flash to
  light-mode users. `values-night/styles.xml` points at a second drawable,
  which is also how this reaches API 24-25 — a `drawable-night/` qualifier
  needs API 29.
- **The adaptive foreground is opaque and black-backed, not matted.** The
  artwork sits on a textured near-black and its darkest ink (the navy outline,
  `#111240`) is barely brighter than that texture, so any alpha-from-luminance
  matte eats the outline. The background layer is the same black, so an opaque
  foreground is pixel-identical to a perfect matte over it, with no keying
  artifacts — the mask clips both layers and parallax moves black over black.
- **The monochrome layer knocks the kanji out of the petals.** Android 13+
  themed icons use only the alpha channel, so a filled silhouette would be an
  anonymous blob. Keeping the navy as a *hole* means the tinted icon still
  reads as 才 in a sakura.
- **`monochrome` in the `-v26` file is deliberate, and it is safe.** The element
  arrived in API 33 while the file is selected from API 26, so it reaches
  platforms that predate it. `AdaptiveIconDrawable.inflateLayers()` matches each
  child against "background" and "foreground" and ends with a bare `continue`,
  so an unrecognised child is skipped rather than rejected — verified in AOSP on
  `android12-release`, which is API 31 and predates the element entirely. It is
  also the shape Android Studio's own Image Asset Studio emits. Filed as a Major
  by `codeant-ai` and declined on those facts; the reasoning is pinned in the
  XML so the next reader does not re-raise it.
- **The launch window cannot honour a *forced* theme, only the system's.**
  Android picks `values-night` from system night mode, and the app's own
  `themeMode` override is not knowable until Dart runs — long after the window
  is drawn. So "system dark + app forced light" still flashes. The complete fix
  is `UiModeManager.setApplicationNightMode` (API 31+), which tells the platform
  the app's night mode so resource resolution follows it; that needs a platform
  channel and only takes effect from the *next* launch, so it is tracked
  separately. The split is still right: `themeMode` defaults to `system`, so the
  two system-following rows are the default experience and both are now
  flash-free, where before one of them always flashed white.

---

### AnymeX is checked out — read the equivalent screen before designing one

**`/home/user/AnymeX-HV`.** It is on disk in every session, and it now decides
both halves — information architecture *and* chrome. It has been skipped at
least once, with a measurable cost.

The repository sheet was designed from scratch. AnymeX's equivalent
(`lib/screens/settings/sub_settings/settings_extensions.dart`, 911 lines) is a
**screen**, not a sheet, and carries four things worth taking: the URL split
into a monospace *path* over a muted *host*, a **copy** button, a per-row
deleting state (spinner plus `AnimatedOpacity` 0.4) rather than a blocking
dialog, and an add dialog that accepts **several URLs at once**. Per-repo health
and source counts are the one direction this app leads in — AnymeX shows
neither — so the feature was right and the shell was not.

Worse, the `TabBar` overflow recorded below was **already solved there**.
AnymeX does not use Material's `TabBar`: `AnymeXTabBar`
(`lib/widgets/anymex_widgets/anymex_tabbar.dart`) is a segmented control built
from a `Stack`, an `AnimatedAlign` and `FractionallySizedBox(widthFactor:
1 / total)`, with each tab an `Expanded` holding a `Flexible` ellipsised label.
Every tab is a fraction of the available width *by construction*, so the
intrinsic-width negotiation that overflowed at 320, 360 and 384 cannot happen.
Hours went into measuring and patching a bug the blueprint had designed out.

**So: before building a screen, open AnymeX's version of it.** The structural
decisions are already made there, and a difference is worth being deliberate
about rather than accidental. Where this app leads — per-repo health, source
counts — build on AnymeX's shell rather than beside it.

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
| The "unknown status never falls back" rule held in the model and not in the sheet | The model refuses to map an unrecognised `MediaListStatus` onto a known one, on purpose. The edit sheet then seeded `_original?.status ?? current`, so opening it on such a row preselected "Reading" and enabled Save instantly — silently overwriting a status AniList added after this build shipped, with one the user never chose. Third time a rule written in one file was not applied in its neighbour (`isReady` in the Settings row, `isReady` in `signIn`, this). When a rule is worth writing down, grep for its other sites the same hour. |
| A four-state distinction had tests for how it *renders* and none for how it is *decided* | Collapsing `notOnList` back into `unavailable` in the service failed nothing — the row's widget tests covered each state, but nothing asserted the service told a successful-but-empty reply apart from a failed call. That distinction is the entire reason the type changed. Rendering tests are not decision tests; assert the branch where the decision is made, not only where its result is shown. |
| A "signed out asks nothing" test passed with the guard deleted | `AniListAuth.query` already refuses when there is no token, so the service's own `viewer == null` check was covered by somebody else's guard. It earns its keep in a *different* state the obvious test never reaches: an offline launch keeps the stored token deliberately, so `isSignedIn` is true while `viewer` is still null and there is no user id to query by. Found by mutating the guard and watching nothing fail. When a check looks redundant, find the state where it is not — or delete it. |
| A review filed a High for the authorize URL "missing" `redirect_uri` | AniList documents that parameter for the **authorization code** grant, warning it must exactly match the registered one, and omits it from the **implicit** grant, which takes `client_id` alone and redirects to the value in application settings. Applying the suggestion would have turned a working request into a hard OAuth rejection for any build registered with a different redirect. Two findings running where the bot was right about the *shape* and wrong about the *facts*: when a finding rests on an external contract — an API, an index format, a published spec — go and read that contract before touching the code. Declining is the fix; pinning the decision in a test so the next reader does not re-raise it is the rest of the fix. |
| A value and the units it is in came from two different requests | The score was read with `score(format:)` using a **cached** viewer, written once at sign-in and never refreshed, while `SaveMediaListEntry` interprets `score` in the user's *current* format. Change the setting on the website and the app reads 85/100 and writes 85 as a five-star rating. The fix is not a fresher cache, it is asking for the format in the **same response** as the row so the two cannot disagree. General rule: when a number and the scale it is on arrive separately, they will eventually disagree, and the code will not notice. |
| A clamp was documented as handling a format change, and actually destroyed the rating | `clampScore` turned an 85/100 into 5 stars, and the comment above it said that was the point — so the comment described a goal the code met by throwing the user's data away. Found by `codeant-ai`. The closing lesson of this table in its most literal form: the comment was not wrong about *what* the code did, only about whether that was acceptable. When a comment justifies a lossy operation, state what is lost and check that losing it is the intended answer. |
| Read-then-act without a lock, again, two files from the rule about it | `AniListProgressSync` read AniList's progress and then wrote a higher one, unawaited from a page turn. Two chapters finished in quick succession both read the same value, both wrote, and the writes raced — chapter 2 landing first and chapter 1 second leaves AniList *lowered*, which the never-lower rule cannot see because each call was right about what it read. Found by `codeant-ai`. This file already carried the rule (`_withRepoLock`, where two `removeRepo` taps resurrected each other's repository) and the fix is the same: the lock spans **both** steps, because making each one individually atomic changes nothing. **Fourth** time a rule written here was not applied in its neighbour. The tell to look for: any `await` between a read and the write that depends on it, in anything a caller can fire twice. |
| The star row overflowed a 320px phone by 89 pixels, and `flutter analyze` was clean | Five 48px targets plus a clear button need ~330px, which a narrow phone does not have between the sheet's gutters. **Seventh** instance of analyze being structurally blind to layout. A rendered test per *branch* was not enough here — the branch was rendered and passed at the default 800px test viewport. Rendered tests for anything with a fixed-width row need a **narrow width** too; the suite now parameterises the rating control over every format at 320px. |
| A mutation that was really a no-op, reported as a passing guard | `sed` could not match `kDefaultSchemeVariant = DynamicSchemeVariant.fidelity` because `dart format` had wrapped the constant across two lines — so the "default variant" mutation edited nothing and every test passed, which reads exactly like a guard that is not pulling its weight. **Second** time a mutation was silently a no-op for this reason. After applying a mutation, `grep` the file and confirm the text actually changed before drawing any conclusion from the test result; a mutation that fails nothing is either a useless test or an unapplied patch, and those look identical from the output. |
| An assertion was written from the shape of the palette rather than its measurements | "the three inks are three different hues" asserted every pair was more than 60 degrees apart. Petal-ink is 87 and ink-blossom is 136, but petal-blossom is **49**: the pink and the coral are neighbours on the wheel, which is *why* the coral reads as an accent rather than a third voice. The test failed on the artwork, not on a bug. The colours were measured an hour earlier and the bound still got guessed — measure, then assert the number you measured. |
| Passing an RGBA image as its own paste mask, which squares the alpha | `mono.paste(art, at, art)` reads as the careful version of `mono.paste(art, at)` — name the mask explicitly rather than rely on a default. PIL composites **every** band through a mask, alpha included, so against a transparent canvas the result is `a*a`, not `a`. Measured: 12,772 antialiased edge pixels fell to 7,986, about 4,800 of them to fully transparent, and the survivors' mean alpha jumped 112 → 151 — a visibly harder, thinner edge. Found by `codeant-ai`, and confirmed by checking the output was *exactly* `round(a**2/255)` rather than by reasoning about the library. The general shape: an argument that looks like belt-and-braces is worth measuring, because the redundant version and the wrong version are the same call. |
| A lock added where the rule did not apply | The repo-health write got a `_withHealthLock` by analogy with `_withRepoLock`, without checking the rule's own stated precondition: *an `await` between the read and the write*. There is none — `KvHelper` is sync throughout — so the lock guarded nothing. Deleting it failed no test, which is how it was found; the replacement is to keep those methods `void` so the atomicity is structural, and the test now proves it by putting a single `await` in the middle and watching exactly one test fail. The inverse of the four times a needed lock was missing, and the same root cause: applying a remembered rule instead of reading the code it is about. |
| A `TabBar` overflowed on ordinary phones and nobody had looked | Three non-scrollable tabs each report `label + 2 * kTabLabelPadding` as a *minimum*, and the sum passed the screen: measured, 24px over at 320, **11px at 360 and 2.7px at 384**, clean only from 411 up. So the Extensions screen drew an overflow stripe on Pixel-class devices, not just tiny ones, and `flutter analyze` was clean throughout — the **eighth** instance. Found only because a narrow-width test was added for an unrelated feature. Fixed with `FittedBox(fit: BoxFit.scaleDown)` per label, chosen over `isScrollable` by measurement: it leaves the three tab centres at 800px *identical* (133.3 / 400.0 / 666.7) where `isScrollable` moves them to 255 / 414 / 559. The lesson beyond the fix: a layout test at one width proves one width, and the width you think is "narrow" may not be where the bug lives. |
| `flutter test` lists at most 4 failing tests and then says "... and N more" | Grepping the "Failing tests:" block under-reports, and a mutation whose guard *did* fire was read as "nothing failed — the guard is hollow", nearly deleting a working test. Read the `+P -F` counts, which are exact, not the names. Third time this session that truncated or unapplied mutation output produced a wrong conclusion — the other two being a `sed` that matched nothing after `dart format` rewrapped a line, and a slice-based patch that broke compilation so the run reported a load error rather than a test result. **A mutation run is only evidence once you have confirmed the patch applied and read the failure count rather than the failure list.** |
| `git checkout <file>` on an uncommitted file destroys it | Run reflexively while chasing an unrelated overflow, it discarded an entire afternoon's worth of new tests that had never been committed. `git checkout` has no undo for unstaged work. Nothing in the repo protects against this; the habit that does is committing a passing slice before starting to diagnose something else, and never using `git checkout` as a "clean up my probe" reflex — the probe was in a *different* file. |
| Two comments asserting properties the code did not have, written the same hour as the rule about it | The repo-health wrapper's doc said "**every** exit is recorded" while the reconcile transaction sat outside `_refresh`'s try, so a database failure propagated past the record *and* out of `refreshAll`'s untried loop, losing every other repo's result. `RepoHealth.fromJson` said it "returns null rather than throwing" while an out-of-range `checkedAt` reached `DateTime.fromMillisecondsSinceEpoch`, which throws. Both found by `codeant-ai`, in the same PR whose own commit message quoted this table's closing lesson. Writing the lesson down is not applying it: after writing a comment with "every" or "never" in it, go and find the path where it does not hold. |
| A reproduction whose trigger did not exist | The database-failure finding was "reproduced" with two repos listing one `sourceId`, on the assumption the unique index would reject it. `Source.sourceId` is `@Index(unique: true, replace: true)`, so it **replaces** — the refresh succeeded and the test failed on its own premise, not on the bug. The finding was still correct (the block is outside the try); only the trigger was invented. When a reproduction fails, check whether it disproves the finding or merely your guess about how to provoke it, and read the annotation rather than assuming the index behaves the obvious way. |
| A stale-answer test that could not tell stale from fresh | The repo sheet's generation guard was "proven" by a gated stub whose `getRepos` returned the field's **current** value. So the held-open reload, on resuming, produced the *newer* data too — both reloads yielded the same thing, and dropping the stale answer was indistinguishable from publishing it. Removing the guard failed nothing. The fix is one line in the fake: snapshot before awaiting the gate. Whenever a test is about *which of two answers wins*, the two answers have to actually differ at the moment each is produced, and a fake that reads mutable state at completion time silently guarantees they do not. |
| A scope read from the wrong side of the widget that publishes it | `ChromeHeaderScope` tells a body how much room the floating header is taking, and answers **0** when there is none — which is right for a converted row dropped into a sheet. `ExtensionsScreen` read it from its own `State`'s `context`, which sits *above* the `ChromeScaffold` that `build` returns, so the lookup found nothing and took that fallback. What it produces is the first row rendered *behind* a translucent, blurred pill: it reads as a design flourish rather than as a row nobody can press, and `flutter analyze` was clean — the **ninth** instance of that blindness. The rendered test at 320/360/384 failed on its first run, which is the only reason it was ever seen. The general shape: a default that is correct for one caller makes a lookup silently wrong for every other, so an `of(context)` with a fallback needs a test that the *right* context was used, not only that the value is sane. |
| A widget that did not fit its slot was erased rather than clipped | The header gives every action a tight 48px box so the header's height is its own property. Measured, an `IconButton` with a 64px icon behind 24px of padding rendered a 48x48 button around a **0x0** icon — an invisible control, with no exception, no overflow stripe, `flutter analyze` clean and no failing test. Clipping is loud and this was silent, which is worse: the **tenth** instance of analyze being blind to layout, and the one class of defect a shared vocabulary must not have when nine more screens are about to be built on it. Fixed with `FittedBox(fit: BoxFit.scaleDown)` *inside* the slot, measured to be a no-op at scale 1.0 for every action that already fits — the same argument as the tab labels two rows up. The general shape: when a parent forces a size, ask what happens to a child that cannot meet it, because "too small to see" and "not there" render identically. |
| A touch-target test measured the render box, not the screen | It asserted `getSize`, which is the **pre-transform** size: 48 for an action that fits and 112 for one scaled down to the slot. So a control the user meets at 48 would have satisfied a test whose name promises 48, by reporting a number that is not on screen. `getRect` is post-transform and is the only one a finger touches. Raised as a weak-test complaint by `codeant-ai`, which was right that the test was weak and named a different reason. Whenever a widget can be scaled, rotated or otherwise transformed between layout and paint, a size assertion has to say which of the two numbers it means. |
| An entire subsystem was built while the reference app on disk already had it | `lib/source/` is 4,361 lines implementing the Mangayomi Dart runtime. `anymex_extension_runtime_bridge` — the plugin AnymeX depends on, whose repo is one `git clone` away and whose name is in AnymeX's own `pubspec.yaml` — implements the same thing from the same upstream, plus six other backends. Phase 1 never checked. This is the row two below it ("Building a screen without opening AnymeX's version of it") at the scale of the whole architecture, and the *third* time in this project: a screen, a widget, now a subsystem. The tell each time was identical — a survey (`ls`, `grep`, a pubspec skim) reported as a deep dive. A survey tells you what files exist; it does not tell you what they do. **Before building any layer, `clone` the reference's dependencies and read the seam, not the directory listing.** Cost here: 4,361 lines, plus a stated rewrite rationale that had to be rewritten, plus a catalogue ceiling 6x below what was available the whole time. |
| Building a screen without opening AnymeX's version of it | The repository sheet was designed from scratch while `/home/user/AnymeX-HV` sat on disk with a 911-line equivalent that is a screen rather than a sheet, splits the URL into monospace path over host, offers copy, dims and spins a row being deleted, and adds several URLs at once. Worse, the `TabBar` overflow two rows up was already designed out there: `AnymeXTabBar` gives each tab `1 / total` of the width with an ellipsised label, so it *cannot* overflow, while this app reached for Material's `TabBar` and then spent a long stretch measuring and patching it. The feature (per-repo health and counts) was genuinely net-new and AnymeX has nothing like it — but the shell around it was reinvented worse. Read the blueprint's version of a screen *before* designing one, not after a review finds the bug it had already avoided. |

The general lesson, and the one that keeps recurring across both codebases:
**a comment describing the goal is not evidence the code achieves it.** After
writing a comment that asserts a property, re-read the code as if you had not
written it and find the path where the property does not hold.
