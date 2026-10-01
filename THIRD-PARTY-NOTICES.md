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
| DXVK for macOS | `dxvk/` | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | LGPL-2.1-or-later |
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

## Wine and DXMT come from CrossOver

Procyon does not ship, download, or update its own Wine or DXMT:

- At launch it runs the Wine inside your installed CrossOver app
  (`Contents/SharedSupport/CrossOver/bin/wine`). Whatever Wine version your
  CrossOver ships is the version Procyon uses, so upgrading CrossOver is what
  upgrades Wine here.
- DXMT is provided by CrossOver as well, and is selected at launch with
  `CX_GRAPHICS_BACKEND=dxmt`. It is not in `Procyon/Libs/`.

The `wine/` snapshot listed above is a set of Gcenx-patched components bundled
with the app; it is not a complete, updatable Wine runtime.

## Versions

The exact upstream versions of the bundled binaries have not been recorded in
this repository. They are fixed snapshots, not auto-updating. When you cut a
release, recording the source tag or commit for each `Libs/` component here is
worth doing so that downstream redistributors can trace what they are shipping.