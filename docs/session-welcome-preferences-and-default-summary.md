# Welcome Preferences Entry Points and Default Summary Prompt

## Overview
This session added convenience entry points and defaults to help users get started faster:
- surfaced the Start on Login toggle on the welcome page,
- added a Preferences button next to Get Started,
- introduced a default custom prompt named Summary,
- and removed ellipses from the Preferences label for a cleaner UI.

## Key Changes

### 1) Start on Login toggle on Welcome
The welcome screen now exposes the Start on Login setting so users can enable it immediately without navigating to Preferences.

Files:
- `Sources/digger/Welcome/WelcomeView.swift`
- `Sources/digger/Welcome/WelcomeViewModel.swift`

Implementation details:
- Added a checkbox bound to `WelcomeViewModel.startOnLogin`.
- Reused the same persistence and SMAppService sync logic as Preferences, including a guard against re-entrant updates.
- The view model updates both stored preference and system login item status, and then reconciles the actual system state.

### 2) Open Preferences button on Welcome
Added a dedicated Preferences button on the welcome page, placed to the left of Get Started.

Files:
- `Sources/digger/Welcome/WelcomeView.swift`
- `Sources/digger/Welcome/WelcomeWindowController.swift`
- `Sources/digger/App/Digger.swift`

Implementation details:
- `WelcomeView` now accepts an `onOpenPreferences` callback and triggers it from the button.
- `WelcomeWindowController` exposes `onOpenPreferences` and passes it into the SwiftUI view.
- `Digger.main()` wires the callback to `PreferencesWindowController.show()`.

### 3) Default Custom Prompt: Summary
Custom Prompts now ship with a default entry for summarization when no saved prompts exist.

File:
- `Sources/digger/Preferences/AppPreferences.swift`

Implementation details:
- Introduced `defaultCustomFunctions` containing:
  - title: "Summary"
  - prompt: "Summarize it in one sentence."
- `customFunctions()` returns this default when no saved data exists or decoding fails.

### 4) Preferences label without ellipsis
Removed trailing ellipses from the Preferences label to match the rest of the UI.

File:
- `Sources/digger/UIStrings.swift`

Implementation details:
- Updated the localized `menuPreferences` strings in English, Chinese, and Japanese.

## Notes
- The welcome page now provides both a quick settings toggle and a direct route to Preferences without blocking the Get Started flow.
- Defaults only apply when user-defined Custom Prompts are missing or invalid.
