<img width="80" height="80" alt="Procyon" src="https://github.com/user-attachments/assets/0efef770-6c63-4f4c-93de-881f6cd68443" />

# Procyon

A Steam game launcher for macOS that can run both Windows and macOS games.
It's based on CrossOver, so you need to install CrossOver first.

Upstream project by [@italomandara](https://github.com/italomandara). This is a fork with the private backend removed, the third-party dependencies removed, and support for large libraries. See [Changes in this fork](#changes-in-this-fork).

> **This is a vibe-coded fork.** The changes in this fork were written with heavy AI assistance, with a human directing and reviewing the work. That is worth being explicit about, because upstream [asks contributors not to submit AI-generated code](https://github.com/italomandara/Procyon). Treat this fork accordingly: it is not endorsed by upstream, it has not been reviewed by its maintainers, and it may contain mistakes. Test the games you care about, and use your own judgement before relying on it.

## What it does

- Replaces CXPatcher: it patches your copy of CrossOver with the latest DXMT and DXVK, and adds an interface for launching Steam games
- Per-game launch options, including graphics backend and Vulkan backend
- Runs 32-bit games faster with x87 via Rosetta x87
- Can run Doom 2016 using the experimental MoltenVK build
- Can run UE4 games via DXVK using the UE4 hack (enabled by default)

![Library](https://github.com/user-attachments/assets/6ed53e07-5a66-4ada-90d6-f6134e7a275b)

![Detail page](https://github.com/user-attachments/assets/ec5ef2ad-b15c-4971-8673-68c9eec83beb)

![Options](https://github.com/user-attachments/assets/a545beda-814c-4bb7-a042-4b85c0322f34)

## Requirements

- macOS 26.2 or later
- CrossOver 26 or the CrossOver preview
- A bottle with Steam installed

## Setup

1. Download and install CrossOver.

2. In Procyon's options panel, select your unpatched CrossOver app. Procyon patches it for you.

3. Open the patched CrossOver from Procyon using the CrossOver button, and install Steam into a bottle.

4. Open the Procyonized Steam from Procyon and log in. Configure your Steam folders there. Steam library folders in other bottles and on external drives are detected too, so you don't have to reinstall games.

5. Open the options panel again and re-select the bottle from the dropdown. Procyon scans your library folders and populates the library. Wait for the analysis to finish. Install games from Steam itself — Procyon lists only what is installed (see [Installing games](#installing-games)); there is no local ownership list.

## Changes in this fork

### Removed the private API backend

Upstream fetched game metadata, the owned-games list, and profile data from a Procyon backend, configured through `API_URL`, `API_KEY`, and related values in `Config.xcconfig`. That backend is gone, so the app no longer needs configuration to work.

Game metadata now comes from Valve's public Store endpoint:

```
https://store.steampowered.com/api/appdetails?appids=<id>&l=<language>&cc=<country>
```

This needs no API key and no account. It is the same data the Store front end uses.

Profile data (display name, avatar, Steam ID) is read from `loginusers.vdf` in your local Steam installation, and the library is built entirely from the local `appmanifest_*.acf` files.

Two consequences:

- **The library shows only installed games.** Steam keeps no licence list on disk, so "owned but not installed" is not knowable offline; Procyon doesn't guess. Use **Install games in Steam** to add games, and they appear after the install writes its manifest.
- **Cold starts still need network** for store metadata. Once cached, your library loads offline. Local manifests and profile work fully offline.

### Removed all Swift Package dependencies

The project had three package dependencies. All three are gone, replaced with code in `Procyon/Util/`:

| Was | Now | File |
| --- | --- | --- |
| Alamofire 5.11.1 | `URLSession` with bounded-concurrency fan-out, retry, and adaptive pacing | `HTTPClient.swift` |
| Kingfisher 8.8.0 | `NSCache`-backed async image loader with request coalescing | `ImageLoader.swift` |
| SwiftUI-Flow 3.1.1 | Custom `Layout` implementation | `WrappingStack.swift` |

The app now has no external package dependencies at all: no `Package.resolved`, no SPM checkout step, and no framework embedding. Clone, open, build.

### Scales to large libraries

The changes needed to keep a large library usable:

- **Adaptive request pacing.** Steam's Store API sits behind Akamai, which answers request bursts with HTTP 403 rather than just 429. The old fixed-concurrency approach got an entire client IP blocked partway through a large load. `RequestPacer` now paces requests, treats 403 and 429 the same way, and shrinks its window on throttle while growing it back on sustained success.
- **Rate-limited games are retried, not dropped.** A throttled fetch is distinguished from "this game has no Store page". Throttled games are collected and retried after a pause, so a large load never silently shrinks the library. Only genuinely absent store pages get blacklisted.
- **Progressive rendering.** Games appear in the grid as each one resolves instead of waiting for the slowest response.
- **Indexed metadata lookup.** `GameThumbnail` used to scan the whole `gamesMeta` array per thumbnail, which is O(n²): at 1000 games that was a million string constructions per render. Lookups now go through a dictionary built once per load, measured ~320x faster at 1000 games.
- **Memoized sort and filter.** `filteredGames` re-sorted the library on every view that read it. The result is now cached and invalidated only when the library, filter, or sort order actually changes.

### Patches CrossOver with the latest DXMT and DXVK

Patching a CrossOver is the point of this app, and a patched CrossOver is only as good as the components in it. Upstream shipped fixed binary snapshots in `Procyon/Libs/`, so a fresh checkout always patched with whatever those snapshots happened to be.

The patcher now resolves the newest upstream release of each component and installs that:

| Component | Source | Installed into |
| --- | --- | --- |
| DXMT | [`3Shain/dxmt`](https://github.com/3Shain/dxmt) | `lib/dxmt/{x86_64-unix,i386-windows,x86_64-windows}` |
| DXVK | [`Gcenx/DXVK-macOS`](https://github.com/Gcenx/DXVK-macOS) | `lib/dxvk/{i386-windows,x86_64-windows}` |

Both use the `-builtin` release variants, which are plain DLL/SO pairs meant to be dropped into a Wine prefix. For each one the patcher asks the GitHub releases API for the latest tag, downloads the matching asset, extracts it, and copies the payload over the copied app. Archives are cached under `~/Library/Caches/Procyon/downloads/components/`, keyed by tag, so re-patching is quick and works offline once a version has been fetched. Use *Delete all downloads cache* in Options to force a refetch.

**Wine is not downloaded, and its core is not overlaid either.** There is no upstream Wine release that is safe to drop into a current CrossOver — `Gcenx/macOS_Wine_builds` only publishes generic `wine-devel`/`wine-staging` trees, and mixing a Wine from a different vintage into a bottle is the surest way to break it. CrossOver's own Wine is left completely intact, including `ntdll` and `win32u`.

An earlier version of this fork overlaid the Wine core components from a bundled snapshot. That does not work: `ntdll.so` is the first library every Wine process loads, and the bundled copy was a different Wine vintage than the CrossOver build it was dropped into, so the runtime failed before any program could start:

```
wine: failed to load start.exe: c000000d
```

That broke Steam and every other launch. Only D9VK is overlaid now, over `lib/wine/`:

| Component | Why |
| --- | --- |
| `d3d9.dll` (D9VK) | `d3d9`, which DXVK has not shipped for a long time |

D9VK is a self-contained drop-in for a single library, so it is safe to install regardless of the Wine vintage underneath it. If you patched with an older build, re-patch from Options: the patcher now removes the stale `ntdll`/`win32u`/`winedmo`/`winegstreamer` files it used to install, which repairs an already-broken patched app. Nothing outside the patched copy is ever touched.

D9VK is installed from the bundle and DXVK from its upstream release, with the bundled DXVK snapshot as fallback. If a download fails (offline, GitHub rate limit, unexpected release layout) the patcher logs it and falls back to the bundled snapshot, and DXMT is skipped so CrossOver's own DXMT is left in place. You never end up with a half-installed component.

CrossOver's own `winegstreamer` needs to be pointed at the GStreamer plugins in the same CrossOver build, so launches also set `GST_PLUGIN_SYSTEM_PATH`, `GST_PLUGIN_PATH` and `GST_PLUGIN_SCANNER`; without them video playback fails silently.

### Finds the game Steam actually launched

Windows games are tracked by reading Steam's own `gameprocess_log.txt` from the
bottle, which names the real process for an app id. The previous approach walked
the game's install directory collecting every `.exe` and polled for a process
name, which matched launcher stubs and helper executables ahead of the game and
missed games that rename or relocate their binary. Native games have no such log
and still fall back to process polling. Once the game is up its window is brought
to the front, and when it exits Steam is given a chance to finish its cloud sync
before being shut down.

### Installing games

The library is built from the `appmanifest_*.acf` files in your Steam library folders, so it only ever shows games that are actually installed. There is deliberately no "owned but not installed" list, because that cannot be determined locally: Steam records no licence list on disk. `appcache/librarycache/` is a display cache that includes DLC, tools and demos, and `appinfo.vdf` carries no ownership data at all, so anything derived from them shows your whole library rather than what you own.

Instead, use **Install games in Steam** in the library toolbar (also in Options). It opens CrossOver and starts Steam for the selected bottle; install from there as usual. The install writes a real `appmanifest_*.acf`, so the next scan picks the game up and it appears in Procyon with a Play button.

### Fixed Steam launching

The launcher and CrossOver integration were fixed to keep:

- `WINEPREFIX` set to the selected bottle for every launch
- `CX_ROOT` exported so CrossOver helpers resolve
- Steam installations on bottle drives (`Z:`, etc.) resolved to the real macOS path
- wineserver and `config.json` handled correctly at launch and shutdown
- Per-version resource filtering so the patched components are actually the ones that get loaded

## Known limitations

- Games have to be installed from Steam itself; Procyon only lists what is installed (see [Installing games](#installing-games)).
- Steam metadata requires a network connection on first load.
- This is a work in progress. Use at your own risk.

## Credits

Thanks to:

- [@Lifeisawful](https://github.com/Lifeisawful) for Rosetta x87
- [@Gcenx](https://github.com/Gcenx) for the patched Wine components and DXVK macOS builds
- [@nastys](https://github.com/nastys) for the UE4 MoltenVK hack
- [CodeWeavers](https://www.codeweavers.com) for CrossOver
- Valve for the public Store API

## Licence

Procyon is licensed under the [GNU General Public License v3.0](LICENSE.txt), the same as upstream.

This fork is a derivative work and is distributed under the same terms. That means:

- Keep `LICENSE.txt` and this attribution intact.
- If you redistribute a build, you must also offer the corresponding source under the same licence.
- The bundled binaries in `Procyon/Libs/` come from third-party projects under their own licences. Redistributing this fork redistributes those binaries, so their notices must be preserved too. See [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

Note that upstream asks contributors not to submit AI-generated code. That is a project policy about contributions to upstream, not a restriction of the GPL, and it does not apply to this fork.

## Contributing

Issues and pull requests are welcome. Test your changes before opening a PR.