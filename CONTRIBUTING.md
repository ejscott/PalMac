# Contributing to PalMac

Thank you for helping make native Palworld modding on macOS safer and more
accessible.

## Before opening an issue

- Search existing issues.
- Confirm the issue occurs with the native macOS build, not CrossOver, Wine,
  or a Windows installation.
- Record the Palworld version and revision shown by PalMac.
- Disable unrelated mods and reproduce with the smallest possible package.
- Do not attach copyrighted game assets or third-party mods without permission.
- Do not post security vulnerabilities publicly; follow [SECURITY.md](SECURITY.md).

## Development setup

Requirements:

- Apple Silicon Mac;
- macOS 14 or later;
- Xcode command-line tools.

```sh
git clone https://github.com/ejscott/PalMac.git
cd PalMac
swift test
swift build
```

Package the local app:

```sh
zsh Scripts/package-app.sh
open outputs/PalMac.app
```

## Pull requests

1. Create a focused branch.
2. Add tests for behavioral or security changes.
3. Run `swift test`.
4. Keep privileged operations narrowly scoped.
5. Update user and mod-author documentation when behavior changes.
6. Explain compatibility and security consequences in the pull request.

Small, reviewable changes are preferred. Avoid unrelated formatting rewrites.

## Security invariants

Changes must preserve these boundaries:

- mod-provided files are never executed;
- administrator privileges are used only for initial folder ownership;
- packages cannot write outside their package-specific deployment directory;
- uninstall and toggle operations validate every path before changing files;
- symbolic links and unsupported files are rejected;
- the Palworld executable is never patched or replaced.

Any proposal that relaxes one of these invariants needs an explicit threat
analysis and maintainer approval.

## Style

- Prefer straightforward Swift and Foundation APIs.
- Keep UI language understandable to nontechnical users.
- Return actionable errors without exposing secrets or unnecessary local data.
- Add comments where a security boundary would otherwise be easy to weaken.

## Licensing

By submitting a contribution, you agree that it may be distributed under the
MIT License. Only submit work you have the right to contribute.
