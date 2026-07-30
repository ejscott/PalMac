# Security Model

PalMac narrows a mod manager's filesystem and privilege boundary. It does not
sandbox Palworld or establish trust in opaque Unreal content.

## Protected assets

PalMac is designed to protect:

- the Palworld executable;
- original game content outside PalMac's deployment root;
- unrelated user files;
- administrator privileges;
- package metadata and state from being interpreted as commands.

## Trust assumptions

- The signed-in macOS user controls the packages they select.
- Palworld and macOS are outside PalMac's security boundary.
- Unreal archives are untrusted and may be malformed or hostile.
- The local user may edit PalMac's user-owned managed folders.
- Administrator authorization may be granted once for folder preparation.

## Controls

### No mod execution

PalMac copies only `.pak`, `.utoc`, and `.ucas` files. It does not launch
package files, run scripts, load dynamic libraries, invoke post-install hooks,
or evaluate metadata as shell code.

### Path confinement

- Package roots, metadata, thumbnails, and install targets must be real files
  or directories rather than symbolic links.
- Targets must resolve inside the selected package.
- Archive files are flattened into one package-specific deployment directory.
- Duplicate and unsafe filenames are rejected.
- Toggle and uninstall preflight every manifest path before changing anything.
- A manifest file must point directly into its matching deployment directory;
  directory entries must equal that deployment directory exactly.

### Privilege separation

Administrator authorization performs one action: create PalMac's two managed
folders and assign them to the signed-in user. Install, toggle, and uninstall
operations refuse to run as root.

The current alpha uses an AppleScript authorization bridge. A distributed,
notarized binary should use a signed `SMAppService` privileged helper with a
strict request protocol.

### Resource limits

- `Info.json`: 1 MB;
- thumbnail: 10 MB;
- archive: 64 GB;
- package: 128 GB;
- installation preserves at least 1 GB of free disk space.

### Executable-header rejection

Common PE, Mach-O, universal-binary, and script headers are rejected when
disguised as an allowed archive. This prevents simple extension spoofing. It
is not malware scanning.

## Residual risks

### Unreal archives are opaque

A PAK or IoStore archive can contain Blueprints, configuration, assets, or
malformed serialized data. PalMac does not currently inspect its internal
mount point, package graph, imports, Blueprint behavior, or parser safety.
Palworld consumes the archive in its own process.

Consequences can include crashes, save corruption, unintended network
activity through game capabilities, or exploitation of a game/engine
vulnerability. Users must treat mods as code-like content.

### Local user ownership

Password-free management requires two user-owned directories inside the game
bundle. Other software running as that user can modify files there. PalMac
detects unsafe manifests when it performs an operation, but it is not a
continuous integrity monitor.

### Package identity

`PackageName`, author, and version are self-asserted. There is no trusted
author registry or cryptographic package signature in the alpha release.

### Updates

App Store updates may replace or invalidate mod content. A mod built for one
revision can crash or behave incorrectly on another revision.

## User guidance

- Download mods only from authors and sites you trust.
- Prefer packages with published SHA-256 checksums.
- Back up Palworld saves before testing a new mod.
- Install one new mod at a time.
- Close Palworld before changing packages.
- Remove a mod after unexplained crashes or network behavior.
- Never disable macOS security controls merely to install a mod.

## Planned improvements

- Developer ID signing and notarization;
- signed `SMAppService` helper;
- optional author signatures and checksum manifests;
- structural PAK/IoStore inspection;
- mount-point and package-path allowlists;
- reproducible releases with published checksums;
- explicit per-revision compatibility metadata.
