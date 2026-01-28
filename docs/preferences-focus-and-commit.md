# Preferences Focus and Commit Behavior

This document summarizes the preference UI behavior added in this session and explains how it works.

## Goals

- Avoid live formatting while typing numeric values.
- Commit changes when editing ends (focus leaves the field).
- Make focus leave the current input when the user clicks outside or presses Return.

## User-visible behavior

- Numeric and text preference fields no longer update on every keystroke.
- Values are saved when the field loses focus or when Return is pressed.
- Clicking anywhere outside an editable input removes focus from the current input, which triggers the save.

## Implementation overview

All changes live in `Sources/digger/Preferences/PreferencesWindowController.swift`.

### 1) Disable live updates while typing

`controlTextDidChange` now returns immediately, so no changes are written while the user is still typing.

### 2) Commit on end editing

`controlTextDidEndEditing` keeps the existing save logic per field. This is where values are parsed, clamped, and formatted.

### 3) Return key ends editing and removes focus

Two paths ensure Return commits and resigns focus:

- `control(_:textView:doCommandBy:)` intercepts `insertNewline` and calls `window.makeFirstResponder(nil)`.
- `controlTextDidEndEditing` also checks for `NSText.movementUserInfoKey == NSReturnTextMovement` and resigns focus as a fallback.

### 4) Clicking outside inputs resigns focus

Two mechanisms cooperate to make this reliable:

- A `NSClickGestureRecognizer` on the content view calls `handleBackgroundClick(_:)` and resigns focus when the click is not inside an editable text field.
- A local mouse monitor (`NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown])`) catches clicks that the gesture recognizer might miss (for example, on complex subviews). It calls `resignFocusIfNeeded(for:)` with the same hit-test logic.

Because AppKit uses a shared field editor, the active editor is usually an `NSTextView`. The helper `isEditingTextField()` checks both `NSTextView.isFieldEditor` and editable `NSTextField` to ensure focus is cleared reliably.

## Key helpers

- `editableTextField(from:)` climbs the view hierarchy to detect if a click landed inside an editable text field.
- `isEditingTextField()` determines whether the current first responder is an active text editor.

## Notes

- This change is scoped to the Preferences window only and does not alter the popup or selection UI.
- The click-to-blur behavior is intentionally permissive: any click outside editable inputs dismisses focus.
