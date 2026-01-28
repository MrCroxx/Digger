# Popup Shortcut Preferences

This document describes the configurable keyboard shortcut that triggers the same pop-up flow as a force click.

## Overview

- The pop-up can be triggered by a global shortcut in addition to force click.
- The default shortcut is Cmd+Ctrl+E (user-editable).
- The shortcut is captured and stored in Preferences, then used by the event tap to trigger the pop-up.

## Preference Storage

- `AppPreferences.popupShortcut()` loads the stored key code and modifiers.
- Defaults are defined in `AppPreferences` and used when no value is stored.
- `AppPreferences.setPopupShortcut(_:)` persists the selection to `UserDefaults`.

## UI: Shortcut Recorder

- `ShortcutRecorderField` is a custom `NSTextField` used in Preferences.
- It captures key events while focused and converts them into a `KeyboardShortcut`.
- Local event monitoring is used so Cmd-based combos are still captured even if the system tries to treat them as menu key equivalents.
- Esc cancels recording and clears focus without changing the shortcut.

## Matching and Triggering

- `KeyboardShortcut` normalizes modifiers to a fixed set (Cmd/Ctrl/Opt/Shift).
- `KeyboardShortcut.matches(event:)` compares both key code and modifiers.
- `EventTapController` checks for the stored shortcut on `keyDown` and triggers `selectionHandler.handleForceClick()` when matched.
- Autorepeat keyDown events are ignored to avoid repeated triggers.

## System Shortcut Conflicts

- Cmd+Ctrl+D is reserved by macOS for Look Up. If the event tap cannot intercept it, the system dictionary will appear instead.
- The default was moved to Cmd+Ctrl+E to avoid this conflict.
- If the event tap is not registered (missing Accessibility permissions), system shortcuts will win.

## Files

- `Sources/digger/Preferences/AppPreferences.swift`
- `Sources/digger/Preferences/KeyboardShortcut.swift`
- `Sources/digger/Preferences/ShortcutRecorderField.swift`
- `Sources/digger/Preferences/PreferencesWindowController.swift`
- `Sources/digger/EventTap/EventTap.swift`
- `Sources/digger/UIStrings.swift`
