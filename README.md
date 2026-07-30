# PalMac

PalMac is an open-source, native macOS mod manager for the Apple Silicon
version of Palworld.

It installs Mac-compatible Unreal Engine packages without patching or replacing
the Palworld executable. PalMac is currently an **alpha project for developers
and testers**. It is not yet a signed or notarized consumer release.

> [!WARNING]
> Mods are untrusted input. PalMac never executes files supplied by a mod and
> strictly limits where it copies them, but it cannot prove that an opaque
> Unreal archive is harmless. A malformed or hostile archive is still parsed by
> the game and may exploit game or engine bugs. Install mods only from authors
> you trust and back up important saves.

## Why PalMac exists

The native Mac build uses Unreal's PAK and IoStore formats differently from
common Windows mod workflows. Dropping a Windows `.pak` into the application
bundle often does nothing, and Windows DLL loaders such as UE4SS do not run
natively on macOS.

PalMac provides a small, auditable manager for the part that does work:
Mac-compatible `.pak`, `.utoc`, and `.ucas` content mounted through Unreal's
standard package scanner.

## Current capabilities

- Native SwiftUI interface and command-line tool.
- Detects the native Mac App Store Palworld bundle and game revision.
- Installs only regular `.pak`, `.utoc`, and `.ucas` files.
- Keeps IoStore `.utoc`/`.ucas` pairs together.
- Enables, disables, and uninstalls each package independently.
- Refuses the unsupported dormant-loader executable patch.
- Uses administrator authorization only once to prepare two managed folders.
- Performs normal mod operations as the signed-in user, never as root.
- Rejects traversal paths, symbolic links, duplicate names, unsupported files,
  disguised Mach-O/PE executables, oversized metadata, and unsafe manifests.
- Does not download mods, execute mod scripts, inject libraries, or modify save
  files.

PalMac deliberately does **not** support UE4SS, Lua, LogicMods, PalSchema,
Windows DLLs, or arbitrary installer scripts.

## Mod authoring

- [Mod authoring overview](docs/MOD_AUTHORING.md)
- [Mac texture walkthrough](docs/TEXTURE_STARTER.md)
- [Hybrid model and content conversion workflow](docs/CONTENT_CONVERSION.md)
- [Checker texture starter project](Examples/CheckerTexture/README.md)

The conversion workflow can retain compatible cooked mesh data while replacing
platform-specific textures and materials with Mac-cooked overlays. It does not
automatically make Windows shaders, scripts, DLLs, or arbitrary Blueprints
portable.

## Tested configuration

The current proof of concept was tested with:

- Palworld for macOS 1.0.4, App Store revision `100933`;
- Apple Silicon;
- macOS 14 or later;
- Unreal Engine 5.1.1 content;
- legacy PAK v11 and UE5.1 IoStore packages.

Game updates can change asset paths, package IDs, container behavior, and
compatibility. Treat the values above as a tested snapshot, not a promise about
future Palworld releases.

## Install for local testing

PalMac is source-only during the alpha security review.

Requirements:

- Apple Silicon Mac;
- macOS 14 or later;
- Xcode command-line tools;
- the native Mac App Store build at `/Applications/Palworld.app`.

Build the app:

```sh
git clone https://github.com/ejscott/PalMac.git
cd PalMac
swift test
zsh Scripts/package-app.sh
open outputs/PalMac.app
```

The first mod change asks for administrator approval. PalMac creates and gives
the current user ownership of only:

```text
/Applications/Palworld.app/Contents/UE/PalMac
/Applications/Palworld.app/Contents/UE/Pal/Content/Paks/~PalMacMods
```

The game executable and original content remain outside PalMac's writable
scope. Close Palworld before installing, toggling, or removing a mod.

## Command-line use

```sh
swift build -c release
.build/release/palmac status
.build/release/palmac validate /path/to/ExampleMacMod
.build/release/palmac install /path/to/ExampleMacMod
.build/release/palmac disable ExampleMacMod
.build/release/palmac enable ExampleMacMod
.build/release/palmac uninstall ExampleMacMod
```

`validate` is read-only. Install and management commands operate only in
PalMac's managed directories.

## Package format

```text
ExampleMacMod/
├── Info.json
└── Paks/
    ├── ExampleMacMod.pak
    ├── ExampleMacMod.ucas
    └── ExampleMacMod.utoc
```

```json
{
  "ModName": "Example Mac Mod",
  "PackageName": "ExampleMacMod",
  "Version": "1.0.0",
  "MinRevision": 100933,
  "Author": "Example Author",
  "Description": "A short description.",
  "InstallRule": [
    {
      "Type": "Paks",
      "Targets": ["./Paks"]
    }
  ]
}
```

The `Paks` directories may contain only `.pak`, `.utoc`, and `.ucas` files.
See [Package Format](docs/PACKAGE_FORMAT.md) for the complete schema and
validation rules.

## For mod authors

Content must target the Unreal version and asset paths used by the installed
Palworld Mac build. Windows containers are not automatically Mac-compatible:

- cooked textures and materials commonly contain platform-specific data and
  usually need to be recooked for Metal;
- Windows shader maps cannot run on macOS;
- some non-shader assets can work after conversion to UE5.1 IoStore, but this
  is asset-dependent and experimental;
- UE4SS and DLL-based mods require a native script-loader project and are
  outside PalMac's current scope.

Start with [Mod Authoring](docs/MOD_AUTHORING.md) and
[Package Format](docs/PACKAGE_FORMAT.md). The
[Checker Texture starter project](Examples/CheckerTexture/README.md) provides
a complete, reproducible UE 5.1.1 Mac cook and IoStore packaging example. Do
not commit or redistribute copyrighted game assets.

## Security model

PalMac treats package metadata and manifests as hostile:

- package roots and install targets cannot be symbolic links;
- archive names are constrained and copied into one package-specific folder;
- uninstall and toggle operations preflight every manifest path and refuse
  anything outside that same package folder;
- package files are copied atomically and never launched;
- privileged execution is restricted to initial managed-folder setup;
- package and disk-space limits reduce accidental resource exhaustion.

These controls protect the filesystem boundary. They do not make an Unreal
archive trustworthy. Read the full [Security Model](docs/SECURITY_MODEL.md)
and [Security Policy](SECURITY.md) before distributing PalMac or accepting
unknown mods.

## Build and test

```sh
swift test
swift build -c release
zsh Scripts/package-app.sh
```

The project has no third-party runtime dependencies. CI runs the test suite on
an Apple Silicon macOS runner.

## Roadmap

- Developer ID signing and notarization.
- Replace the prototype authorization bridge with a signed `SMAppService`
  helper before shipping a consumer binary.
- Cryptographic package checksums and optional trusted-author signatures.
- Deeper PAK/IoStore structural validation.
- Explicit game-version compatibility profiles.
- Reproducible release archives and published checksums.
- A documented Mac cooking/conversion toolkit for mod authors.
- Texture, material, mesh, and script compatibility guides based on
  reproducible test projects.

## Contributing

Issues and pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md), the
[Code of Conduct](CODE_OF_CONDUCT.md), and [SECURITY.md](SECURITY.md).
Security reports must not be filed as public issues.

## Support the project

If PalMac becomes useful to you, GitHub Sponsors can be enabled for
[`@ejscott`](https://github.com/ejscott). Contributions, testing, documentation,
and safe Mac-native mods are equally valuable.

## License and disclaimer

PalMac is available under the [MIT License](LICENSE).

PalMac is an independent community project. It is not affiliated with,
endorsed by, or supported by Pocketpair, Epic Games, Apple, Nexus Mods, or the
Palworld development team. Palworld and related names and assets belong to
their respective owners. No game assets are included in this repository.
