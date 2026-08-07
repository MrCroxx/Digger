# Digger

A macOS menu bar app that detects force-click selection and runs customizable AI prompts on selected text.

![Digger Icon](Sources/digger/Resources/digger.png)

## Features

- Force-click selection trigger based on trackpad pressure delta.
- Menu bar workflow with popup results near the cursor.
- Multiple prompt functions executed in parallel for one input.
- Streaming and non-streaming response modes.
- Disk cache with configurable size and TTL.
- Configurable OpenAI endpoint, model, and reasoning effort.
- Localized UI (English, Simplified Chinese, Japanese).
- Built-in onboarding for Accessibility permission and setup tips.

## Requirements

- macOS 13 or later
- Xcode 16+ (or Swift 6.2 toolchain)
- Network access to your configured OpenAI-compatible endpoint
- Accessibility permission granted for Digger

## Quick Start

1. Clone this repository.
2. Build and run from source:

```bash
swift build
swift run digger
```

3. Open **Preferences** from the menu bar item and configure:
   - API key
   - Model
   - Endpoint (optional, defaults to `https://api.openai.com/v1`)
4. Grant Accessibility permission when prompted.
5. Select text and use the popup shortcut (default: `Command + E`) to run prompts.

## Build Artifacts

Create a release `.app` bundle (and DMG by default):

```bash
./scripts/build-app.sh
```

Build configuration defaults are in:

- `scripts/build-config.sh`

Common outputs:

- App bundle: `dist/Digger.app`
- DMG: `dist/Digger-<version>.dmg`

## Project Structure

```text
Sources/digger/
  App/            App bootstrap and menu wiring
  Core/           Force-click monitoring logic
  EventTap/       Global event tap integration
  Selection/      Text selection and popup action flow
  Translation/    OpenAI client and disk cache
  Preferences/    Settings models and SwiftUI views
  Welcome/        First-run onboarding window
  UI/             Popup and menu bar UI components
  Resources/      App assets
scripts/          Build and packaging scripts
docs/             Design notes and implementation logs
```

## Runtime Configuration

Most runtime settings are managed in-app via Preferences and persisted with `UserDefaults`, including:

- OpenAI API key / model / endpoint / reasoning effort (`THINK_EFFORT`)
- Force-click thresholds
- Popup behavior and shortcut
- Prompt list and system prompt
- Streaming toggle
- Cache size and TTL
- Language selection

## Notes

- Digger is currently distributed as source-first; signed/notarized release flow is available through `scripts/build-app.sh` when signing credentials are configured.
- The app relies on Accessibility APIs. Without permission, trigger handling is disabled.

## Contributing

Issues and pull requests are welcome. Please include:

- Clear reproduction steps for bugs
- Expected vs actual behavior
- Environment details (macOS version, model/endpoint config if relevant)

## License

No license file is currently included in this repository.
