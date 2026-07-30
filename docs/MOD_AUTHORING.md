# Mod Authoring for Palworld on macOS

This guide documents the current experimental workflow. It does not include
game assets, proprietary tools, or permission to redistribute another
creator's work.

For a working project rather than a conceptual overview, start with the
[Checker Texture starter](../Examples/CheckerTexture/README.md) and follow the
[texture walkthrough](TEXTURE_STARTER.md).

For a model conversion that combines compatible legacy mesh data with
Mac-cooked texture or material replacements, use the
[content conversion workflow](CONTENT_CONVERSION.md).

## Compatibility classes

Classify a mod before attempting a conversion:

| Class | Typical content | Mac approach |
| --- | --- | --- |
| Direct candidate | Data assets and some meshes without custom shaders | Convert the container to UE5.1 IoStore, then test |
| Recook required | Textures, materials, meshes with platform data | Recreate or import the author-owned source in UE 5.1.1 and cook for Mac |
| Native rewrite required | UE4SS, Lua, Windows DLLs, executable patches | Requires a future Mac-native loader or a new implementation |
| Unknown | Blueprints, complex dependencies, undocumented custom versions | Inspect dependencies and test in isolation; do not promise compatibility |

Container conversion does not convert DirectX shaders into Metal shaders and
does not make Windows DLLs portable.

## Start with a small content-only mod

Good first tests:

- one texture replacement;
- one static mesh;
- one skeletal mesh using an existing native Palworld material;
- a harmless, visible UI texture.

Avoid script loaders, gameplay Blueprints, custom shaders, and large model
packs until the basic mount path is proven.

## Match the game

The tested Palworld Mac build uses Unreal Engine 5.1.1-era content and IoStore.
Before building:

1. Record the Palworld version and bundle revision.
2. Confirm the exact long package path of the asset being replaced.
3. Use the matching Unreal Engine version.
4. Cook for the `Mac` target.
5. Preserve the original package and object names.

## Platform-specific assets

### Textures

Windows-cooked textures may use platform-specific formats. Extracting the
source image and recooking it for `Mac` is the reliable approach. Visible color
textures normally use sRGB; masks and data textures normally do not. Match the
source asset's compression and streaming settings when known.

### Materials

Windows material packages can contain DirectX shader maps such as DXBC. Those
shaders cannot run on Metal and commonly appear as a grey fallback material.

Preferred approaches:

- create a Mac-cooked material in the matching Unreal version; or
- create a lightweight material instance of an existing Palworld Mac material
  and override compatible parameters such as `Base Texture`.

The second approach reuses shaders already shipped by the game and avoids
redistributing original material assets.

### Meshes

Some cooked skeletal or static mesh packages can survive legacy-to-IoStore
container conversion, but compatibility is not guaranteed. Materials,
textures, physics assets, Blueprint dependencies, and engine custom versions
must still resolve.

## Legacy-to-IoStore experiments

The open-source `retoc` project can convert some UE5.1 legacy packages to Zen
IoStore:

```sh
retoc to-zen --version UE5_1 InputMod.pak OutputMod_P.utoc
```

This typically produces:

```text
OutputMod_P.pak
OutputMod_P.ucas
OutputMod_P.utoc
```

Retoc is a separate project with its own license and is not bundled with
PalMac. Conversion changes the container, not the cooked platform data.
Windows shaders and platform-specific textures still need a Mac-native
solution.

PalMac includes a guarded builder for a prepared legacy asset tree:

```sh
zsh Scripts/build-content-conversion.zsh \
  --source-root /path/to/LegacySource \
  --overlay-root /path/to/MacCookedOverlay \
  --package-name ExampleModelMac \
  --mod-name "Example Model Replacement (Mac)" \
  --output-root /path/to/Build \
  --plan-only
```

The tool deliberately does not extract untrusted archives. It validates the
prepared inputs, reports which files will be replaced by Mac-cooked overlays,
and can then build and verify the final IoStore triplet.

Use the official Retoc release for your Mac and verify its published checksum.
PalMac does not download or execute third-party modding tools.

## Package for PalMac

Place the finished archives in a PalMac package:

```text
MyModMac/
├── Info.json
└── Paks/
    ├── MyModMac_P.pak
    ├── MyModMac_P.ucas
    └── MyModMac_P.utoc
```

Validate before testing:

```sh
.build/release/palmac validate /path/to/MyModMac
```

Use a unique `PackageName`, declare the minimum tested Palworld revision, and
state whether the mod is a conversion made with the original author's
permission.

## Testing checklist

- Back up saves.
- Close Palworld.
- Disable unrelated mods.
- Install and enable the package.
- Confirm the main menu loads.
- Test the exact asset or outfit replaced.
- Quit normally and inspect crash logs if needed.
- Disable the package and confirm the original behavior returns.
- Uninstall and verify its package directory is removed.

## Distribution checklist

- You have permission to distribute every included asset.
- No original Palworld assets are included unless their license permits it.
- No Windows DLLs, scripts, or unrelated files are present.
- IoStore pairs are complete.
- A SHA-256 checksum is published.
- Tested game revision and known conflicts are documented.
- Users are told to back up saves.
