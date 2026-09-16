<div align="center">
  <img src="Sources/digger/Resources/digger.png" width="96" alt="Digger app icon">
  <h1>Digger</h1>
  <p><strong>Words, made clear.</strong></p>
  <p>A native macOS assistant for translating, summarizing and exploring selected text.</p>
</div>

Select text in another app and press **⌘E**. Digger runs enabled prompts in parallel and displays the answers in a floating window.

![Digger's native result window](docs/images/native-popup.png)

## A native workspace

The interface is built with **SwiftUI + AppKit**, with warm paper surfaces, brown accents, and automatic light/dark appearance. See the [redesign decision and validation notes](docs/native-redesign.md).

The app icon uses a cream serif `d` on a walnut brown tile. Run `swift scripts/app-icon.swift` to regenerate its PNG and all macOS icon sizes.

- **Works where you read** — reads selections through macOS Accessibility; browser HTML is converted locally to Markdown to retain lists and links. Temporary clipboard copies restore the previous clipboard.
- **Your prompts, in parallel** — translation starts enabled and summary disabled; enable, disable, add, edit or remove custom actions and edit a shared system prompt.
- **Bring your model** — configure an OpenAI-compatible endpoint, API key, model and reasoning effort; test the connection from Settings.
- **Stable streaming** — answers arrive in a scrollable window that stays in place. Resize, drag or pin it as needed.
- **Readable results** — streaming Markdown with nested lists, tables, headings, quotes, links, selectable text and literal code blocks.
- **Control the work** — stop a generation, retain partial answers, or retry while bypassing the cache. Closing the window cancels active work.
- **Copy what you need** — source, individual results or all results; `⌘⇧C` copies results, `⌘⌥C` includes the source.
- **Local cache** — configurable capacity and expiration, stored on this Mac.
- **Mac essentials** — menu bar access, a configurable global shortcut, launch at login, permission guidance, English, 简体中文 and 日本語.

Force Touch is no longer used. No trackpad configuration is required.

## Get started

Requirements: macOS 13+, an OpenAI-compatible API, Accessibility permission, and a Swift 6.2+ toolchain for building.

```sh
git clone https://github.com/mrcroxx/digger.git
cd digger
swift run digger
```

1. Grant Digger Accessibility access in System Settings.
2. Open **Settings → API**, enter the endpoint, API key and model, then test the connection.
3. Select text in another app and press `⌘E`.

Existing API settings, prompts and cache are retained when upgrading. If a newly built app is not recognized by macOS Accessibility, grant access to the new build and reopen it. Stable signing avoids repeated identity changes.

## Settings

| Page | Controls |
| --- | --- |
| General | Language, streaming, launch at login |
| Popup | Typography preview, font size, background opacity, shortcut, window dimensions |
| Prompts | Shared system prompt, per-action enable switches and native multiline editors |
| API | Endpoint, key, model, reasoning effort and connection test |
| Cache | Capacity, expiration and cache directory |

Changes save automatically. Tooltips follow native macOS timing.

## Build and validate

The local and CI packaging entry point is the same:

```sh
DIGGER_MAC_UNSIGNED=1 ./scripts/package-desktop.sh
```

This checks the diff, runs the packaging regression tests and all Swift tests against a temporary loopback API, builds Release, signs the app, and verifies a relocated copy before creating the archives. The fixture uses a fake key and never contacts a provider. The mounted DMG and extracted ZIP are checked again, including startup and resource loading with no access to preferences or Accessibility permissions.

Outputs:

- `dist/Digger.app`
- `dist/Digger-<version>-<arch>.dmg`
- `dist/Digger-<version>-<arch>.zip`

Build each architecture on a matching Mac (`arm64` or `x64`). Like Verso, packaging uses macOS `hdiutil` directly, sets both the mounted volume icon and the local DMG file icon, and includes an Applications shortcut. It does not depend on `create-dmg`, a custom background, or Finder automation. The DMG file icon is filesystem metadata; the volume icon is embedded in the image and survives downloads.

`DIGGER_MAC_UNSIGNED=1` explicitly selects ad-hoc signing for local use; these builds are not notarized. To use an installed signing identity and optionally notarize:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARIZE=1 NOTARY_PROFILE="digger-notary" ./scripts/package-desktop.sh
```

The app is signed and stapled before either archive is created. Configure `NOTARY_PROFILE` in Keychain with `xcrun notarytool store-credentials` first. Without `DIGGER_MAC_UNSIGNED=1`, `SIGN_IDENTITY` is required. Environment variables override the defaults in `scripts/build-config.sh`.

For app-only packaging with the same checks, use `DIGGER_MAC_UNSIGNED=1 ./scripts/package-desktop.sh --dir`. For a quick local build without the test suite, use `DIGGER_MAC_UNSIGNED=1 CREATE_DMG=0 ./scripts/build-app.sh`; add `BUILD_CONFIGURATION=debug` for a debuggable bundle. Quit the running app before replacing `/Applications/Digger.app`.

GitHub Actions runs on pull requests and pushes to `main`: macOS 15 with Xcode 26.2 builds Debug and runs the same packaging entry point. Each successful run uploads both archives as `Digger-macOS` for seven days, without requiring API keys or signing certificates.

To verify an existing DMG independently:

```sh
./scripts/verify-dmg.sh dist/Digger-0.0.1-arm64.dmg
```

Review the UI offline in a debug build:

```sh
swift run digger --preview
swift run digger --preview --settings
swift run digger --preview --welcome --dark
```

If a shortcut does not open the popup, stop Digger with `Ctrl+C` and check the current registration from the same terminal:

```sh
swift run digger --diagnose
```

The menu bar also shows the configured shortcut and its status. `--preview` intentionally does not register a global shortcut.

## Data and permissions

Selected text and prompts are sent directly to the API endpoint you configure when you invoke Digger. API settings remain in local preferences. Responses may be cached in `~/Library/Caches/digger/translation-cache`. Digger does not log selected text or generated results.

Accessibility is used for reading the selection. The global shortcut is registered independently, so it can explain missing permissions. Digger does not require trackpad drivers or a browser runtime. Its Markdown renderer does not fetch remote images or execute HTML.

## Structure

```text
Sources/digger/
  App/            Bootstrap, menus and offline debug preview
  EventTap/       Global shortcut and outside-click observation
  Selection/      Accessibility extraction and cancellable prompt execution
  Translation/    OpenAI-compatible client and local cache
  Preferences/    Persisted settings and SwiftUI editor
  Welcome/        Permission guidance
  UI/             Design system, result state, Markdown and floating panel
Tests/            State, geometry, Markdown, endpoint and transport regression tests
scripts/          Local transport fixture, build and packaging
```

Older documents in `docs/` describe historical implementations; [native-redesign.md](docs/native-redesign.md) describes the current architecture.

## License

No license file is currently included in this repository.
