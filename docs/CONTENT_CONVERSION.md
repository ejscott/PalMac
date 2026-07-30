# Content Mod Conversion Workflow

This guide captures the repeatable hybrid workflow proven with a third-party
model replacement during PalMac development. No third-party or Palworld assets
are included in this repository.

The successful result depended on two different operations:

1. compatible cooked mesh and supporting packages were retained from the
   original legacy mod; and
2. the platform-specific texture and material packages were recreated in
   Unreal Engine 5.1.1, cooked for `Mac`, and overlaid at the same paths.

The combined legacy asset tree was then rebuilt and converted to UE5.1
IoStore. Converting only the container produced the model change, but the
Windows material rendered grey. Replacing the texture and material with
Mac-cooked packages corrected the appearance.

## Scope and limits

This workflow is for content-only packages such as textures and some static or
skeletal meshes. It does not convert:

- UE4SS or Lua scripts;
- Windows DLLs or executable patches;
- DirectX shader maps into Metal shaders;
- arbitrary Blueprints or missing dependencies; or
- content created for a different Unreal Engine serialization version.

Only convert and distribute work you own or have permission to modify and
redistribute. Package and object paths are compatibility information, but the
assets stored at those paths may be copyrighted.

## Inputs

Prepare a legacy source directory with this shape:

```text
LegacySource/
└── Pal/
    └── Content/
        └── Pal/
            └── path/to/original/cooked/files
```

Extracting opaque archives is intentionally outside PalMac. Use the original
author's source package and trusted Unreal tooling in a separate working
directory. Inspect the result before passing it to the build tool.

Prepare zero or more Mac overlay directories with the same `Pal/Content`
layout:

```text
MacCookedOverlay/
└── Pal/
    └── Content/
        └── Pal/
            └── path/to/Mac/cooked/files
```

An overlay file replaces a legacy file only when its relative path and
filename match exactly. That is how a Mac-cooked texture or material replaces
the incompatible Windows package without changing references stored in the
mesh.

## Build a conversion plan

Run a dry plan before invoking UnrealPak or Retoc:

```sh
zsh Scripts/build-content-conversion.zsh \
  --source-root /path/to/LegacySource \
  --overlay-root /path/to/MacCookedOverlay \
  --package-name ExampleModelMac \
  --mod-name "Example Model Replacement (Mac)" \
  --output-root /path/to/Build \
  --min-revision 100933 \
  --plan-only
```

The planner:

- accepts only regular cooked Unreal files beneath `Pal/Content`;
- rejects symbolic links and files outside that mount path;
- rejects DLLs, scripts, executables, and unknown extensions;
- reports how many Mac files replace legacy files; and
- does not extract, download, or execute mod-supplied content.

A plan with no Mac overlay may work for a simple direct candidate, but it is
not proof of Mac compatibility.

## Build the PalMac package

Install Unreal Engine 5.1.1 and an Apple Silicon Retoc release from its
official project. Verify third-party downloads independently, then run:

```sh
UNREAL_PAK="/Users/Shared/Epic Games/UE_5.1/Engine/Binaries/Mac/UnrealPak" \
RETOC="/full/path/to/retoc" \
zsh Scripts/build-content-conversion.zsh \
  --source-root /path/to/LegacySource \
  --overlay-root /path/to/MacCookedOverlay \
  --package-name ExampleModelMac \
  --mod-name "Example Model Replacement (Mac)" \
  --version 1.0.0 \
  --author "Original author; Mac conversion by Your Name" \
  --description "Mac conversion made with the original author's permission." \
  --min-revision 100933 \
  --output-root /path/to/Build
```

The tool performs these steps:

1. validates the prepared source and overlay trees;
2. copies them into an isolated temporary staging directory;
3. applies Mac overlays after the legacy source;
4. creates a new intermediate legacy PAK;
5. converts it to a UE5.1 `.pak`/`.utoc`/`.ucas` triplet;
6. runs Retoc verification and lists the result;
7. generates a PalMac `Info.json`;
8. creates a ZIP and SHA-256 checksum; and
9. runs PalMac validation when a release CLI build is available.

The output is:

```text
Build/
├── ExampleModelMac/
│   ├── Info.json
│   └── Paks/
│       ├── ExampleModelMac_P.pak
│       ├── ExampleModelMac_P.ucas
│       └── ExampleModelMac_P.utoc
├── ExampleModelMac.zip
└── ExampleModelMac.zip.sha256
```

## Recreating texture and material overrides

Use the matching long package path and object name in Unreal Engine 5.1.1.
Cook for the `Mac` target, then copy the resulting cooked files from:

```text
Saved/Cooked/Mac/Pal/Content/
```

into the overlay root beneath `Pal/Content/`.

For visible color atlases:

- enable sRGB;
- preserve alpha when it is used by opacity or masks;
- match the original texture role and compression;
- avoid treating normal maps or packed masks as color textures.

For materials, prefer a small Mac-cooked material instance that references a
compatible material already shipped in the native game. Preserve the exact
parameter names expected by that parent. This avoids packaging Windows shader
maps and avoids redistributing the native parent material.

The model used during development required a neutral white color parameter as
well as its base texture. The mesh loaded before that correction, but the
material rendered grey. This is a useful diagnostic distinction:

- no model change usually indicates a mount, target-path, or dependency issue;
- the model changes but appears grey usually indicates material, shader, or
  texture incompatibility.

## Regression record

For every successful conversion, keep a private record containing:

- original mod version and checksum;
- permission or license terms;
- Palworld version and bundle revision;
- Unreal Engine version;
- Retoc version and checksum;
- exact package paths overridden;
- texture sRGB, compression, streaming, and alpha settings;
- native material parent and parameter names used;
- build command;
- output checksum;
- conflicts and required companion mods; and
- enable, disable, uninstall, and clean-launch test results.

Do not commit third-party assets, extracted game content, private paths, or
personal correspondence as regression fixtures. A public regression fixture
should be an original minimal asset like the checker texture example.

## Test checklist

1. Back up saves and close Palworld.
2. Disable unrelated mods.
3. Validate and install the package with PalMac.
4. Confirm the main menu loads.
5. View every replaced model or texture variant.
6. Check colors in more than one lighting condition.
7. Quit normally.
8. Disable the package and confirm native assets return.
9. Re-enable it and repeat the launch.
10. Uninstall it and confirm its managed package directory is removed.

Passing this checklist on one revision is evidence, not a permanent
compatibility guarantee. Re-test after Palworld updates.
