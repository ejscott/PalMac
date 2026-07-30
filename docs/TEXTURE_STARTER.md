# Texture Mod Walkthrough

This walkthrough explains the complete Mac-native texture path demonstrated by
the [Checker Texture starter project](../Examples/CheckerTexture/README.md).
It is intended for original work and conversions made with the original
author's permission.

## The pipeline

```text
Original PNG
    ↓ import at the exact /Game path
UE 5.1.1 Texture2D
    ↓ cook for TargetPlatform=Mac
Mac legacy .uasset/.uexp/.ubulk
    ↓ UnrealPak
intermediate legacy PAK
    ↓ Retoc to-zen --version UE5_1
UE5.1 .pak/.utoc/.ucas
    ↓ PalMac package
installed mod
```

Each step solves a different problem. Cooking creates Mac platform data.
UnrealPak gathers the cooked legacy files. Retoc changes their container and
asset representation to the IoStore form mounted by the tested native game.
PalMac validates and deploys the final triplet.

## 1. Start with source you may distribute

Use an original PNG or source supplied by a mod author who has granted
permission. Do not publish textures extracted from Palworld merely because
they can be opened by an asset tool.

For a Windows mod, ask its author for the original PNG/TGA and usage terms.
Recooking an extracted Windows texture can fix platform compatibility, but it
does not transfer copyright or redistribution rights.

## 2. Find the exact target

An override works only when all three match:

- long package directory;
- package filename;
- Unreal object name.

For example:

```text
/Game/Pal/Model/Character/Player/Outfit/
SK_Player_Female_Outfit_Cloth001/v01/
T_Player_Female_Outfit_Cloth001_v01_M01_B
```

The matching cooked files must retain that directory and basename. Case
matters. A successful mount with no visible change often indicates the wrong
target, outfit variant, or game revision.

## 3. Match texture semantics

Do not apply base-color settings to every texture:

| Suffix or role | sRGB | Typical Unreal compression |
| --- | --- | --- |
| Base color/albedo | On | Default |
| Normal map | Off | Normalmap |
| Masks/packed channels | Off | Masks |
| Emissive color | Usually on | Default |
| Numeric/data texture | Off | Match the original use |

The checker starter replaces only `_B` base-color textures. The native game
continues using its own normal maps and masks, so lighting and material
channels remain intact.

If colors are too dark, washed out, or grey, check sRGB first. A flat grey
material across the whole mesh more often indicates an incompatible material
or shader map rather than a bad base-color PNG.

## 4. Cook on Mac

Use Unreal Engine 5.1.1 and the `Mac` target. Opening or saving an asset in the
editor is not enough; it must be cooked for the target platform.

The starter invokes:

```sh
UnrealEditor-Cmd Pal.uproject \
  -run=Cook \
  -TargetPlatform=Mac \
  -Package=/Game/path/to/ExactAsset \
  -cooksinglepackagenorefs \
  -unversioned -compressed -unattended
```

The first cook can compile global Metal shaders and take substantially longer
than later builds. A shader error is a failed cook even if some cooked files
were created.

## 5. Create IoStore output

The tested native Palworld build did not apply the starter's intermediate
legacy PAK by itself. Convert it with Retoc:

```sh
retoc to-zen --version UE5_1 \
  PalMacCheckerTexture_Legacy.pak \
  PalMacCheckerTexture_P.utoc
```

Retoc writes:

```text
PalMacCheckerTexture_P.pak
PalMacCheckerTexture_P.ucas
PalMacCheckerTexture_P.utoc
```

Keep all three together. Verify before distribution:

```sh
retoc verify PalMacCheckerTexture_P.utoc
retoc list --path PalMacCheckerTexture_P.utoc
```

Retoc is an independent MIT-licensed project and is not bundled with PalMac.
Use its official release and published checksum.

## 6. Package and validate

Place the triplet under `Paks/` beside a PalMac `Info.json`, then run:

```sh
swift run palmac validate /path/to/PalMacCheckerTexture
```

Validation confirms PalMac's package and filesystem rules. It cannot prove
that the Unreal content is compatible, harmless, or legally distributable.

## 7. Test safely

1. Back up saves.
2. Close Palworld.
3. Disable unrelated mods.
4. Install and enable the package.
5. Launch the same game revision used during development.
6. Equip or view the targeted outfit.
7. Disable the package and verify the original appearance returns.

## Troubleshooting

### The game loads but nothing changes

- Verify the package is enabled in PalMac.
- Confirm the `.pak`, `.utoc`, and `.ucas` basenames match.
- Check the exact package/object path and letter case.
- Confirm the active character/outfit uses that texture variant.
- Recheck the game revision.
- Use `retoc list --path` to verify the target asset is in the container.

### The mesh is grey

- Do not reuse a Windows-cooked material containing DirectX shader maps.
- Prefer a Mac-cooked material or a material instance based on a native game
  material.
- Confirm every texture and material dependency resolves.

### Colors are wrong

- Base color should normally have sRGB enabled.
- Masks, normal maps, and numeric data should normally have sRGB disabled.
- Match the original compression and channel packing where known.
- Avoid replacing mask or normal textures with a color image.

### The game crashes

- Disable the package immediately.
- Test one asset at a time.
- Confirm UE 5.1.1, Mac cooking, and complete IoStore output.
- Check for missing dependencies or a package built for another game revision.
- Do not redistribute a package that crashes during a clean test.

## Converting a Windows texture mod

A responsible conversion is a rebuild, not just a filename change:

1. obtain permission and the author's original source image;
2. record the Windows mod's exact target path;
3. import that source at the same path in the starter project;
4. reproduce the correct sRGB, compression, and channel settings;
5. cook for Mac;
6. build and verify UE5.1 IoStore;
7. package with a new `PackageName`, attribution, tested revision, and notes;
8. publish a SHA-256 checksum and document the original author's permission.

If the Windows mod includes a material, mesh, Blueprint, UE4SS script, Lua
file, or DLL, treat it as a different conversion class. A working texture
pipeline does not make those components portable.
