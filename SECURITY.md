# Security Policy

## Supported versions

PalMac is currently alpha software. Security fixes are applied to the latest
commit on the default branch. No older release line is supported yet.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability.

Use the repository's **Security → Advisories → Report a vulnerability** flow.
Private vulnerability reporting will be enabled when the public repository is
created. Include:

- affected commit or version;
- impact and attack scenario;
- minimum reproduction steps;
- whether user interaction or administrator authorization is required;
- suggested mitigation, if known.

Please avoid accessing data that is not yours, persistence, destructive tests,
or publishing details before a fix is available.

## Response goals

This volunteer project aims to:

- acknowledge a report within 7 days;
- provide an initial assessment within 14 days;
- coordinate disclosure after a fix or mitigation is available.

These are goals, not a service-level agreement.

## Scope

Examples of in-scope issues:

- package or manifest paths escaping PalMac's managed directories;
- symbolic-link or race-condition attacks that change unintended files;
- mod operations unexpectedly running as root;
- command injection through package metadata or helper requests;
- unsafe update, signing, or release behavior;
- secrets committed to the repository or release artifacts.

Generally out of scope:

- a malicious Unreal archive affecting Palworld after the user deliberately
  installs it, unless PalMac could reasonably have detected or contained it;
- vulnerabilities in Palworld, Unreal Engine, macOS, or third-party mod tools;
- social engineering that asks a user to run unrelated commands;
- denial of service requiring local administrator access.

PalMac does not claim to sandbox mods. Treat every mod as untrusted code-like
content and install only from trusted authors.
