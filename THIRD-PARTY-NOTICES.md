# Third-party notices

Procyon bundles the binaries listed below under `Procyon/Libs/`. They are
redistributed as part of this project under their own licences, and those
licences must be preserved when redistributing a build of this fork.

This file is an inventory, not a substitute for the upstream licence texts.
The binaries here carry no embedded licence notices, so for any component you
redistribute you should obtain the licence text from the project's own
repository and keep it alongside the binary.

## Bundled components

| Component | Path | Upstream | Licence |
| --- | --- | --- | --- |
| Wine (patched macOS port) | `wine/` | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds), patched sources [Gcenx/wine](https://github.com/Gcenx/wine) (shipped via CrossOver) | LGPL-2.1-or-later |
| DXVK for macOS (fallback snapshot) | `dxvk/` | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | LGPL-2.1-or-later |
| D9VK | `d9vk/` | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) | LGPL-2.1-or-later |
| MoltenVK | `libMoltenVK-latest.dylib`, `libMoltenVK-experimental.dylib` | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Apache-2.0 |
| Vulkan driver (macOS) | `libvulkan_kosmickrisp.dylib`, `kosmickrisp_mesa_icd.x86_64.json` | [KosmicKrisp (Mesa)](https://docs.mesa3d.org/drivers/kosmickrisp.html), prebuilt by [crueter-ci/KosmicKrisp](https://github.com/crueter-ci/KosmicKrisp) | Apache-2.0 |
| Rosetta x86_64 shim | `libRuntimeRosettax87`, `runtime_loader` | [Lifeisawful/rosettax87](https://github.com/Lifeisawful/rosettax87) | See upstream |
| CrossOver | Not bundled; required separately | [CodeWeavers/CrossOver](https://www.codeweavers.com/crossover/) | Proprietary |

## Before redistributing a build

1. Fetch the licence text for each component from the links above.
2. Keep each licence next to its binary, or in a `licenses/` directory that
   ships with the app bundle.
3. Keep this file included.

## Downloaded at patch time

These are not redistributed with the app. The patcher fetches the newest release
of each from its upstream repository and installs it into the patched CrossOver
copy, so a build of this fork does not ship them. If you redistribute a build,
you are not redistributing these, but you are making users' machines download
them.

| Component | Source | Licence |
| --- | --- | --- |
| DXMT (release `-builtin` assets) | [3Shain/dxmt](https://github.com/3Shain/dxmt) | LGPL-2.1-or-later (Wine components) |
| DXVK for macOS (release `-builtin` assets) | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | LGPL-2.1-or-later |

## Wine components come from the bundle

Procyon does not download a Wine runtime. The launcher runs the Wine inside your
installed CrossOver app (`Contents/SharedSupport/CrossOver/bin/wine`), so
upgrading CrossOver is what upgrades Wine.

The patcher does, however, install one bundled component into the patched copy,
because it is a self-contained drop-in for a single library and so does not
depend on the Wine vintage underneath it:

| Bundled path | Source | Licence |
| --- | --- | --- |
| `d9vk/x32/d3d9_builtin.dll`, `d9vk/x64/d3d9_builtin.dll` | [DualCoder/d9vk](https://github.com/DualCoder/d9vk) | LGPL-2.1-or-later |

Earlier versions of this fork also overlaid the Wine core (`ntdll`, `win32u`,
`winedmo`, `winegstreamer`) from a bundled `Gcenx/macOS_Wine_builds` snapshot.
That is not done any more, and those files are no longer bundled: `ntdll.so` is
the first library every Wine process loads, so installing one from a different
Wine vintage than the target CrossOver broke the runtime outright
(`wine: failed to load start.exe: c000000d`), preventing Steam and every other
program from starting. Patching now removes any such files left behind by an
older build. Nothing outside the patched copy is modified, and re-patching from
Options rebuilds the copy from your installed CrossOver.

DXMT is selected at launch with `CX_GRAPHICS_BACKEND=dxmt`. It is not in
`Procyon/Libs/`: it is downloaded from `3Shain/dxmt` at patch time, and
CrossOver's own copy is used if that download fails.

## Versions

DXMT and DXVK are fetched from their upstream releases at patch time, so the
version that ends up in a patched CrossOver is whatever was newest when you
patched. Record it if you need to reproduce a specific patched app.

The bundled binaries are fixed snapshots with no recorded source tag. They are
now only used as fallbacks and for the Wine overlay, but they are still installed
unconditionally, so their vintage matters. When you cut a release, recording the
source tag or commit for each `Libs/` component here is worth doing so that
downstream redistributors can trace what they are shipping.