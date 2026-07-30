# Changelog

All notable changes to PalMac will be documented here.

## [Unreleased]

### Planned

- Developer ID signing and notarization.
- Signed privileged helper for consumer distribution.
- Cryptographic package identity and deeper archive inspection.

## [0.3.0] - 2026-07-30

### Added

- Native SwiftUI package inspector and mod manager.
- CLI status, validation, install, enable, disable, and uninstall commands.
- One-time managed-folder setup for password-free mod operations.
- Quick launch for the native Palworld app.
- PAK and IoStore package support.
- Minimum game-revision checks.
- Open-source documentation, contribution guide, security policy, and CI.

### Security

- Mod file operations refuse to run as root.
- Install targets and metadata reject symbolic links and traversal.
- Paks targets accept only regular `.pak`, `.ucas`, and `.utoc` files.
- IoStore pair, filename, metadata-size, package-size, and disk-space checks.
- Common executable headers are rejected when disguised as archives.
- Toggle and uninstall operations confine tamperable manifests to the matching
  package-specific deployment directory.

### Compatibility

- Tested with Palworld for macOS 1.0.4 revision `100933`.
- Windows DLL and UE4SS workflows remain unsupported.
