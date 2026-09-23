# Development and packaging

Digger requires macOS 13+ and a Swift 6.2+ toolchain. The interface uses
SwiftUI and AppKit; the package is defined in [Package.swift](../Package.swift).

## Run locally

```bash
swift run digger
```

Configure a provider in Settings and grant Accessibility permission to the
build you are running. Existing API settings, prompts, and cache are retained
when upgrading.

For a regular installation, use a stable signing identity. Replacing an
ad-hoc signed build can change its identity to macOS, requiring Accessibility
access to be granted again. Quit the running app before replacing
`/Applications/Digger.app`.

## Build an installer

The local and CI entry point is the same:

```bash
DIGGER_MAC_UNSIGNED=1 ./scripts/package-desktop.sh
```

It checks the diff, runs packaging regression tests and Swift tests against
a temporary loopback API, builds Release, signs the app, and verifies a
relocated copy before creating the archives. The transport fixture uses a
fake key and does not contact an AI provider. The mounted DMG and extracted
ZIP are checked again, including startup and resource loading.

Outputs:

- `dist/Digger.app`
- `dist/Digger-<version>-<arch>.dmg`
- `dist/Digger-<version>-<arch>.zip`

Build on a Mac matching the target architecture (`arm64` or `x64`). Packaging
uses macOS `hdiutil` and includes an Applications shortcut. It does not install
the app. Environment variables override [build-config.sh](../scripts/build-config.sh).

For app-only packaging with the same checks:

```bash
DIGGER_MAC_UNSIGNED=1 ./scripts/package-desktop.sh --dir
```

For a quick local build without the test suite:

```bash
DIGGER_MAC_UNSIGNED=1 CREATE_DMG=0 ./scripts/build-app.sh
```

Add `BUILD_CONFIGURATION=debug` for a debuggable bundle.

## Signing and notarization

`DIGGER_MAC_UNSIGNED=1` selects ad-hoc signing; these builds are not notarized.
Use an installed signing identity for stable local builds:

```bash
SIGN_IDENTITY="Your Installed Code Signing Identity" ./scripts/package-desktop.sh
```

For distribution with a Developer ID certificate and notarization:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARIZE=1 NOTARY_PROFILE="digger-notary" ./scripts/package-desktop.sh
```

Configure `NOTARY_PROFILE` in Keychain with `xcrun notarytool store-credentials`
first. The app is signed and stapled before the archives are created. Without
`DIGGER_MAC_UNSIGNED=1`, `SIGN_IDENTITY` is required.

## Validation

```bash
swift test
python3 scripts/test-popup-layout.py
/usr/bin/python3 scripts/test-transport.py
git diff --check
```

The native layout checks exercise streaming, scrolling, resizing, dark mode,
and automatic sizing with offline fixtures. Run preview commands sequentially:
they share an isolated preferences domain and the Swift build directory.

To verify an existing DMG independently:

```bash
./scripts/verify-dmg.sh dist/Digger-0.0.1-arm64.dmg
```

[CI](../.github/workflows/ci.yml) runs on pull requests and pushes to `main`.
It builds Debug and runs the packaging entry point on macOS 15 with Xcode 26.2.
Successful runs upload the DMG and ZIP as **Digger-macOS**, retained for seven
days, without requiring provider keys or signing certificates.

## Offline previews and screenshots

```bash
swift run digger --preview --showcase --english
swift run digger --preview --settings --english
swift run digger --preview --welcome --dark
python3 scripts/capture-readme.py
```

Preview mode is available in Debug builds. It uses isolated preferences,
does not register a global shortcut, and renders example responses without
calling a provider. See [screenshot provenance](images/README.md) for the
capture scenes and language options.

## Shortcut troubleshooting

Stop the locally running instance with `Ctrl+C`, then check registration from
the same terminal:

```bash
swift run digger --diagnose
```

The menu bar also shows the configured shortcut and its registration status.
Confirm Accessibility access for the actual build being launched. Do not use
`--preview` to verify the global shortcut: preview mode intentionally skips it.

## Source layout

```text
Sources/digger/
  App/            Bootstrap, menus, and offline debug previews
  EventTap/       Global shortcut and outside-click observation
  Selection/      Accessibility extraction and cancellable prompt execution
  Translation/    OpenAI-compatible client and local cache
  Preferences/    Persisted settings and SwiftUI editor
  Welcome/        Permission guidance
  UI/             Design system, results, Markdown, and floating panel
Tests/            State, geometry, Markdown, endpoint, and transport checks
scripts/          Transport fixtures, screenshots, builds, and packaging
```
