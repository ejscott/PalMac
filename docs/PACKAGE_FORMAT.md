# PalMac Package Format

PalMac packages are directories selected by the user. They contain declarative
metadata and one or more Unreal archives. They do not contain installers or
scripts.

## Directory layout

```text
ExampleMacMod/
├── Info.json
├── Preview.png              # optional
└── Paks/
    ├── ExampleMacMod.pak
    ├── ExampleMacMod.ucas   # optional IoStore data
    └── ExampleMacMod.utoc   # required with matching .ucas
```

Files in an install-rule target must be immediate children of that directory.
Nested directories and symbolic links are rejected.

## `Info.json`

```json
{
  "ModName": "Example Mac Mod",
  "PackageName": "ExampleMacMod",
  "Thumbnail": "Preview.png",
  "Version": "1.0.0",
  "MinRevision": 100933,
  "Author": "Example Author",
  "Description": "A short description.",
  "Dependencies": ["AnotherPackage"],
  "InstallRule": [
    {
      "Type": "Paks",
      "Targets": ["./Paks"]
    }
  ]
}
```

### Fields

| Field | Required | Constraints |
| --- | --- | --- |
| `ModName` | Yes | 1–128 characters |
| `PackageName` | Yes | 1–64 ASCII letters, numbers, or underscores |
| `Version` | Yes | 1–64 characters; semantic versioning is recommended |
| `MinRevision` | No | Minimum Palworld bundle revision |
| `Author` | No | Up to 128 characters |
| `Description` | No | Up to 4,096 characters |
| `Thumbnail` | No | Regular file inside the package, at most 10 MB |
| `Dependencies` | No | Informational in the alpha release |
| `InstallRule` | Yes | 1–16 rules |

Only the `Paks` install-rule type is supported. Server rules with
`"IsServer": true` are ignored by the native client manager.

## Archive rules

- Allowed extensions: `.pak`, `.ucas`, `.utoc`.
- Archive names are 1–128 ASCII letters, numbers, dots, underscores, or
  hyphens, and must begin with a letter or number.
- Names are unique without regard to case.
- Every `.ucas` requires a same-basename `.utoc`, and vice versa.
- Each file must be nonempty and no larger than 64 GB.
- A complete package must be no larger than 128 GB.
- Files with common Windows PE, Mach-O, universal-binary, or script headers are
  rejected even if renamed.
- Unknown files in a `Paks` target are rejected.

These checks are filesystem safety checks, not proof that Unreal content is
benign or compatible.

## Installation destination

`PackageName` determines the only deployment directory:

```text
Palworld.app/Contents/UE/Pal/Content/Paks/~PalMacMods/<PackageName>/
```

All installed paths are recorded in:

```text
Palworld.app/Contents/UE/PalMac/ManagedMods/<PackageName>/InstallManifest.json
```

PalMac revalidates every manifest path before toggling or uninstalling. A
manifest cannot authorize changes outside its matching package directory.

## Compatibility

Filename validation cannot determine cooked platform compatibility. Packages
must target the installed Palworld Mac build and its Unreal version. Windows
shader maps, DLLs, and script loaders are not portable.
