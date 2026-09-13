# Feature checklist

The scope, written down rather than remembered. Compiled from exhaustive sweeps
of the two reference apps — the Kotlin
[Otaku-Reader](https://github.com/HeartlessVeteran2/Otaku-Reader) (79 shipped
features by issue number) and [AnymeX](https://github.com/RyanYuuki/AnymeX) —
plus [Komikku](https://github.com/komikku-app/komikku) for library/browse UX.

`[x]` = shipped here. `[ ]` = not yet. Anime-only features are omitted.

---

## Phase status

- [x] **0 — Skeleton.** Isar + recovery ladder, `KvHelper`, typed enum keys, M3 theming, `LazyIndexedStack` shell, explicit DI.
- [x] **1 — Source runtime.** Mangayomi Dart extensions via d4rt. 55/55 evaluate, 6 complete the full chain.
- [ ] **2 — Browse, details, library, home** (incl. AniList details Overview).
- [ ] **3 — Reader.**
- [ ] **4 — Downloads, updates, history.**
- [ ] **5 — Smart Prefetch, AniList metadata, Smart Panels.**
- [ ] **6 — Tracking fan-out, migration, stats, Komikku parity.**
- [ ] **7 — AniList profile, search/calendar/AI picks, compatibility.**

---

## Reader

The single most important surface. Combined list from both apps.

**Modes & layout** — [ ] paged and continuous · [ ] 4 directions (LTR/RTL/top-down/bottom-up) · [ ] dual-page (off/auto-landscape/force) with **shift double pages** · [ ] auto webtoon mode (switches to vertical from page aspect ratios) · [ ] fit-to-screen-width · [ ] webtoon side padding and page gap · [ ] image width multiplier + desktop max-width clamp · [ ] spaced pages

**Rendering** — [ ] tiled/subsampled decoding for tall strips (AnymeX's `subsampling_scale_image_view/` + FFI decoder) · [ ] crop borders (white/black margin removal) · [ ] image filter quality incl. Lanczos pre-scale · [ ] image quality / data-saver downscaling · [ ] pinch + double-tap zoom, disable-zoom-out option

**Navigation** — [ ] customisable tap zones, **four profiles** (paged/webtoon × horizontal/vertical) · [ ] navigation-mode presets (Default, L, Kindlish, Edge, Right-and-Left, Disabled) · [ ] invert tapping (none/horizontal/vertical/both) · [ ] volume keys + invert + **per-mode overrides** + hold-to-skip-5 · [ ] keyboard/DeX shortcuts · [ ] mouse wheel + trackpad · [ ] overscroll to prev/next chapter · [ ] **navigate by chapter number** (skips duplicate/scanlator dupes) · [ ] auto-scroll with speed, **pause-on-touch and auto-resume**

**Display** — [ ] custom brightness (AnymeX goes to −75) · [ ] colour filter with **RGBA sliders and 16 blend modes**, plus named presets · [ ] custom tint + opacity · [ ] greyscale · [ ] invert · [ ] reader background (9 options) · [ ] **e-ink flash** with duration/interval/colour · [ ] keep screen on · [ ] fullscreen + cutout handling · [ ] orientation lock (7 modes) · [ ] secure screen (`FLAG_SECURE`)

**Chrome** — [ ] reader control theme registry (default/iOS) · [ ] page indicator · [ ] page slider with haptic tick · [ ] **page thumbnail strip** (slider ⇄ filmstrip) · [ ] full-page gallery grid · [ ] in-reader chapter list with search + asc/desc + list/grid · [ ] chapter transition cards with **missing-chapter gap warning** · [ ] reading timer overlay · [ ] battery + clock overlay · [ ] zoom indicator

**Actions** — [ ] long-press page: save / share / copy URL / set as cover · [ ] page bookmark toggle · [ ] in-chapter download button · [ ] reader comments + chapter note · [ ] reader presets (save/apply/delete) · [ ] per-manga reader overrides + reset-to-global · [ ] incognito mode

**Exclusive to the Kotlin app** — [ ] Smart Prefetch (4 strategies, behaviour tracking, telemetry) · [ ] Smart Panels (**net-new: the Kotlin app has no detector**, only auto-crop + a UI shell) · [ ] SFX translator · [ ] OCR page translation · [ ] OCR text search across pages

---

## Library

[ ] Display modes (grid/comfortable/list/cover-only) + staggered · [ ] portrait/landscape column counts + **pinch to change columns** · [ ] badges (unread, downloaded, completed, NEW, type) · [ ] title on cover · [ ] category tabs with counts · [ ] grouping (category/source/status/tracker/none) · [ ] **11 sorts** + asc/desc · [ ] **tri-state filters** (downloaded, unread, started, bookmarked, completed, tracking, dropped, source, reading list, genre, has-notes) · [ ] active-filter chips + clear all · [ ] **saved filter/sort views** · [ ] FTS search + advanced search (`author:` / `tag:` syntax) · [ ] greeting header · [ ] daily-goal card · [ ] continue-reading carousel · [ ] recommendations with dismiss · [ ] tablet two-pane detail panel

**Categories** — [ ] create/edit/delete/reorder · [ ] **hidden** (biometric-gated) · [ ] NSFW · [ ] locked · [ ] per-category update frequency · [ ] skip-updates toggle · [ ] **dynamic/smart categories** (11 rule types)

**Bulk actions** — [ ] select all / invert / deselect · [ ] mark read/unread · [ ] download · [ ] move category · [ ] remove **with undo** · [ ] notify toggle · [ ] mark completed/dropped · [ ] share · [ ] migrate · [ ] update selected · [ ] search globally · [ ] confirmation dialogs

**Maintenance** — [ ] refresh covers/metadata · [ ] reindex downloads · [ ] scan + delete orphaned files · [ ] **merge duplicates** + link alternative source + fill missing chapters · [ ] cross-source duplicate detection

**Reading lists** — [ ] create/edit/delete · [ ] export CSV/JSON

---

## Details

[ ] Header: cover (tap = **panorama toggle**), title, author/artist, status, expandable description, genre chips (tap = search, long-press = global search), stats row, **read-time estimate** · [ ] custom cover set/remove · [ ] **Edit Info** sheet writing `user*` override columns + reset-to-source · [ ] content type toggle (manga/manhwa) · [ ] cover theme override cycle · [ ] AI summary

[ ] Action row: library toggle, tracking, WebView, share, refresh · [ ] overflow: migrate, mark completed/dropped, download all/unread, open download folder, clear downloads, add to reading list, link to AniList, notify toggle, delete-after-read override · [ ] category picker on first favourite

**Chapter list** — [ ] sort asc/desc · [ ] search · [ ] filter sheet (read/downloaded/**scanlator**) · [ ] **scanlator pills** · [ ] **chapter range/chunk pills** · [ ] per-chapter progress + time estimate · [ ] thumbnail preview · [ ] note preview · [ ] per-chapter menu (mark read/unread, mark previous read, download, delete, **export CBZ**) · [ ] multi-select · [ ] continue-reading highlight · [ ] tile styles (compact/detailed/grid)

**Source binding** — [ ] source picker with search + type tabs + language sub-picker · [ ] **wrong-title remap**

---

## AniList (full AnymeX parity — see `CLAUDE.md` for the query set)

**Details Overview tab**, in order — [ ] quick actions (list status, custom list) · [ ] progress bar · [ ] synopsis · [ ] stats grid (score, format, status, origin, chapters, popularity, source, studio) · [ ] alternative titles · [ ] genres · [ ] **tags with rank %** · [ ] social "friends reading this" · [ ] seasons/prequel-sequel · [ ] **characters carousel** · [ ] **relations carousel** · [ ] **staff carousel** · [ ] **recommendations carousel**

> AnymeX guards its Extras section with `if (controller.isAnime)`, so manga never
> gets **Recent News**, **Anime Adaptation** ("adapted from ch. X–Y") or
> **Next Release Prediction**. All three are written and MangaUpdates-backed.
> Ship them for manga — that is an improvement on AnymeX, not parity with it.

- [ ] Character / staff detail sheets (paged media lists)
- [ ] **List entry editor**: status, score in **all five AniList formats** (POINT_100 / POINT_10_DECIMAL / POINT_10 / POINT_5 / POINT_3, read from the user's own account settings), progress, start/finish dates, private, delete. *(AniList's `repeat` and `notes` are net-new — AnymeX never touches them.)*
- [ ] Long-press **peek popup** for quick list editing
- [ ] Home: MANGA LIST / OTHER buttons, per-status carousels driven by `homePageCards`, **Recommended Manga excluding what you've already read**, community recommendations
- [ ] Profile: header, stats tab (genres/tags/staff, count/time/mean-score metrics), favourites, activity feed + replies + likes, social tab
- [ ] **Compatibility checker** (weighted heuristics; already has a full manga path)
- [ ] Advanced search + `fetchFilterData` introspection (genres, tags, formats, statuses, sources, chapter/volume ranges)
- [ ] AniList account settings mirror (title language, score format, section order, custom lists)
- [ ] List exporter (MAL-compatible XML)
- [ ] AI picks

---

## Downloads, updates, history

[ ] Queue with pause/resume/cancel/retry/move-to-front · [ ] **survives restart** (persisted queue) · [ ] foreground notification with progress · [ ] concurrency + chunk settings · [ ] download location picker · [ ] **CBZ export + AES-256 encryption** · [ ] auto-download new chapters + per-category include/exclude · [ ] download-ahead · [ ] **smart downloads** (trigger at % through a chapter, wifi/favourites/free-space gates) · [ ] delete-after-read + **keep-last-N** · [ ] data saver · [ ] storage analytics with per-entry delete · [ ] data usage dashboard + monthly budget

[ ] Updates: group by manga/date · [ ] date filters · [ ] **to-be-updated sheet** · [ ] **last-run summary** (checked/new/skipped/failed) · [ ] multi-select · [ ] undo · [ ] **update errors screen** (sticky headers, migrate-selected)

[ ] History: search · [ ] date-range filter · [ ] **date section headers** · [ ] swipe-to-delete + undo · [ ] multi-select · [ ] resume

---

## Everything else

**Sources/extensions** — [ ] repo management · [ ] auto-update · [ ] language filter · [ ] NSFW gate · [ ] **pin + hide + categorise sources** · [ ] saved source searches · [ ] **persisted per-source filter state** · [ ] source health diagnostics · [ ] extension detail screen · [ ] **signer hash provenance** · [ ] blocklist · [ ] install from URL/file · [ ] Cloudflare WebView session bridge

**Tracking** — [ ] AniList + MAL (+ Kitsu/MangaUpdates/Shikimori later) · [ ] **bind one manga to N trackers and fan out** · [ ] 95%-read threshold with **progress-regression guard** · [ ] per-tracker sync-on-read toggle · [ ] batch sync · [ ] tracking health page

**Backup/sync** — [ ] selective backup/restore with **pre-backup checklist and pre-restore preflight** · [ ] **AES-256-GCM encryption** · [ ] auto-backup schedule + retention · [ ] Tachiyomi/Mihon import · [ ] cloud backup (WebDAV) · [ ] cross-device progress sync · [ ] QR library share/scan

**Settings** — [ ] **settings search with deep-link and row highlight** · [ ] theme (seed/Material You/custom + variants + OLED + schedule) · [ ] **per-cover auto theme** · [ ] font family picker · [ ] **reorderable + hideable nav tabs** · [ ] UI multipliers (glow/radius/blur/roundness/animation duration) · [ ] card/carousel/navbar style registries · [ ] grain texture · [ ] liquid wallpaper · [ ] refresh-rate picker · [ ] advanced (user-agent override, DoH, verbose logging, clear cookies, battery optimisation, don't-kill-my-app) · [ ] storage manager with per-bucket sizes + auto-clear threshold · [ ] logs to file

**Security** — [ ] biometric app lock + **time/day schedule** · [ ] incognito · [ ] encrypted credential stores · [ ] certificate pinning · [ ] crash handler with copy-to-clipboard · [ ] opt-in crash reporting (user-supplied DSN)

**Other** — [ ] onboarding wizard · [ ] home-screen widgets + **configuration studio** · [ ] Discord RPC with **editable presence templates** · [ ] deep links + app shortcuts · [ ] share · [ ] statistics (streaks, heatmap, achievements, goals, **share card with anonymise toggle**) · [ ] **XP/rank tiers** · [ ] feed/discovery · [ ] migration wizard with **configurable flags incl. notes + custom cover** and range-select · [ ] local source (CBZ/ZIP/EPUB/folders, ComicInfo.xml) · [ ] OPDS (Komga/Kavita) · [ ] in-app updater with beta channel · [ ] **SauceNAO reverse image search** · [ ] notification batching + quiet hours + hide-content

---

## Deliberately not doing

- **Anime and video playback.** Manga-first; the runtime port already strips 20 video extractors.
- **A second source backend.** Dart + JS covers the ecosystem; the APK backend exists in the Kotlin app only for catalogue size, which no longer applies.
- **Editing extensions or the test fixture** to make a source work. See `CLAUDE.md`.
