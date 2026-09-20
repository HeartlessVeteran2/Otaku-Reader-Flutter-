# Otaku Reader

A manga and manhwa reader for Android, built in Flutter on the
[Mangayomi](https://github.com/kodjodevf/mangayomi) extension ecosystem.

> **Status: early, and the source layer is gaining a second backend.** This
> app's own Mangayomi runtime stays; alongside it,
> [AnymeX's extension bridge](https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge)
> is being adopted for **Tachiyomi/Mihon** extensions, which is where the other
> ~1,400 extension packages are. An earlier plan replaced the runtime instead;
> measuring the two against each other reversed that. See `CLAUDE.md`,
> "The extension bridge". [`ROADMAP.md`](ROADMAP.md) is the plan and
> [`FEATURES.md`](FEATURES.md) is the checklist.

## Why this exists

This is a rewrite of the Kotlin
[Otaku-Reader](https://github.com/HeartlessVeteran2/Otaku-Reader), for one
concrete reason.

Mangayomi publishes its manga sources in **two languages**. Measured against the
live index (363 entries):

| | index entries | distinct scripts | distinct sites |
|---|---|---|---|
| Dart | 249 | 7 | **245** |
| JavaScript | 114 | 18 | 18 |

The seven Dart scripts are site-parameterised templates — `madara.dart` alone
drives 151 sites. **A Dart app can interpret them; a Kotlin one cannot.** The
Kotlin version could only ever run the JavaScript half, which is why it kept a
second, APK-based backend alive purely for catalogue size.

That argument is still right about *why a Dart rewrite*, and it was wrong about
what follows: "so no second backend" reads as a pure win, and it is a trade.
Even reaching every one of those 245 sites, the ceiling is this ecosystem's,
and the Tachiyomi/Mihon one is ~1,400 packages. So this app keeps a second
backend too — through AnymeX's bridge rather than by loading APKs itself.

A second benefit falls out of the same change: the Dart bridge hands extensions
real element handles rather than HTML strings, so DOM traversal (`parent`,
`children`, `nextElementSibling`) works. The Kotlin app records that as a
deferred limitation costing it two sources.

### Verified, not claimed

Sweeping every English/all-language Dart source against its real site, chaining
`getPopular → getDetail → getPageList`:

```
evaluated:       55 / 55
popular listed:   8
detail+chapters:  6
full chain:       6
```

The remaining failures are external — dead or parked domains, sites that moved,
Cloudflare, network blocks — each checked with `curl` before being ruled out.
Reproduce it yourself with `flutter test tool/source_sweep.dart`.

## Building

Requires **Flutter 3.47.4** exactly (Dart 3.13.3) and JDK 21. The pin is not
cosmetic — see [`CLAUDE.md`](CLAUDE.md#toolchain--do-not-upgrade-these-casually).

```bash
flutter pub get
dart run build_runner build
flutter build apk --debug
```

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). The one rule worth knowing up front:
**published extensions run unmodified.** A source that fails is this app's bug,
never the extension's.

## Credits

Built on the work of three projects — see [`NOTICE`](NOTICE):

- **[Mangayomi](https://github.com/kodjodevf/mangayomi)** (Apache-2.0) — the
  extension runtime and its source ecosystem.
- **[AnymeX](https://github.com/RyanYuuki/AnymeX)** (MIT) — architecture, reader
  design and UI patterns.
- **[Otaku-Reader](https://github.com/HeartlessVeteran2/Otaku-Reader)**
  (Apache-2.0) — feature design and data models.

## License

[Apache-2.0](LICENSE).

This app hosts no content. It reads publicly available sources through
third-party extensions, which are the responsibility of their authors.
