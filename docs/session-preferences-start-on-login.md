# Session Implementation Notes: Start on Login Preference

This document summarizes the implementation work completed in this session to add a “Start on Login” preference and the associated login-item behavior.

## Overview

The session added a new preference toggle that registers/unregisters the app as a login item on macOS 13+. The setting is persisted and kept in sync with the system login-item status.

Key goals:

- Add a Preferences toggle labeled “Start on Login”.
- Persist the toggle state in `UserDefaults`.
- Register/unregister the login item using `SMAppService`.
- Keep the UI in sync with system state if it changes externally.

## Preference Storage

`AppPreferences` now includes a new key and accessors:

- Key: `StartOnLogin`
- Accessors: `startOnLoginEnabled()` / `setStartOnLoginEnabled(_:)`

The stored value is treated as the UI preference, but is reconciled against the system state when Preferences opens and on app startup.

## Login Item Integration

`StartOnLoginManager` encapsulates login-item behavior via `ServiceManagement`:

- `isEnabled()` checks `SMAppService.mainApp.status` and treats `.enabled` and `.requiresApproval` as “on”.
- `apply(enabled:)` registers or unregisters the service based on the toggle.
- `refreshPreference()` reconciles the stored preference with the current system status.

This keeps the toggle accurate even if the user changes login items in System Settings.

## Preferences UI Wiring

The toggle is placed in the General tab, near other primary settings:

- `PreferencesViewModel` exposes `startOnLogin`.
- `PreferencesView` binds the toggle and calls `StartOnLoginManager.apply` on change.
- If registration fails or status differs, the toggle is reset to the actual system state.

## Startup Sync

To ensure the preference reflects external changes:

- `Digger.main()` calls `StartOnLoginManager.refreshPreference()` at app launch.
- `PreferencesWindowController.show()` also refreshes before opening the window.

## Localization

New UI strings were added for the toggle label:

- English: “Start on Login”
- Chinese (Simplified): “登录时启动”
- Japanese: “ログイン時に起動”

## Files and Key Entry Points

- `Sources/digger/Preferences/StartOnLoginManager.swift`
  - Login-item integration and preference sync
- `Sources/digger/Preferences/AppPreferences.swift`
  - New `StartOnLogin` preference
- `Sources/digger/Preferences/PreferencesViewModel.swift`
  - `startOnLogin` state
- `Sources/digger/Preferences/PreferencesView.swift`
  - Toggle UI and apply logic
- `Sources/digger/Preferences/PreferencesWindowController.swift`
  - Refresh before showing Preferences
- `Sources/digger/App/Digger.swift`
  - Refresh at app startup
- `Sources/digger/UIStrings.swift`
  - Label localization

## Notes

- Login item registration requires macOS 13+ (`SMAppService.mainApp`).
- `SMAppService.Status` uses `.notRegistered` for the disabled state.
