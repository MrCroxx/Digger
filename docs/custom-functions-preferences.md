# Custom Functions in Preferences

This document summarizes the custom function framework and UI added in this session, along with the execution flow and persistence model.

## Overview

The app now supports user-defined functions in Preferences. Each function has:

- Title
- Prompt

Functions are unlimited and can be added or removed. Each function maps to a region in the popup, where the title is displayed and the prompt is applied to the selected text. The existing translation behavior is integrated as a built-in function in the same framework.

## Key Components

### Data Model and Persistence

- `Sources/digger/Preferences/CustomFunction.swift`
  - `CustomFunction` struct (id, title, prompt), Codable for storage.

- `Sources/digger/Preferences/AppPreferences.swift`
  - Stores functions under `CustomFunctions` in `UserDefaults` (JSON-encoded array).
  - `customFunctions()` decodes and returns the list (removes bad data on decode failure).
  - `setCustomFunctions(_:)` saves updates.

### Built-in Translation as a Function

- `Sources/digger/Translation/PromptTemplates.swift`
  - Provides the translation prompt template used by both the built-in translation and the unified execution path.

- `Sources/digger/Selection/PopupFunction.swift`
  - `PopupFunction` represents both built-in and custom functions.
  - `availableFunctions()` returns `[translation] + customFunctions`.

### Execution Flow (Parallel)

- `Sources/digger/Selection/ForceClickSelectionHandler.swift`
  - On force-click, fetch selected text and prepare the function list.
  - Shows popup with all sections in a loading state.
  - Executes all functions in parallel using `withTaskGroup`:
    - For each function, the prompt is applied to the selected text.
    - Streaming updates update the corresponding popup section.
    - Errors are surfaced per section.

### Popup Layout

- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - Popup is multi-section, one per function.
  - Each section has a divider, title, and result content.
  - Streaming keeps sections in loading state until final output is received.
  - Copy actions work with all results or the translation section only.

### Preferences UI (Table-based)

- `Sources/digger/Preferences/PreferencesWindowController.swift`
  - Custom functions are displayed in an `NSTableView` (columns: Title, Prompt).
  - Add/Remove controls (`+` / `-`) are in the header, outside the table.
  - Remove is enabled only when a row is selected.
  - Table cells are editable, and edits persist to `UserDefaults`.

## Behavior Details

1. **Add function**
   - Clicking `+` appends a new prompt with a default title and empty prompt.
   - The table selects and scrolls to the new row.

2. **Remove function**
   - Clicking `-` removes the selected row.
   - Button is disabled when nothing is selected.

3. **Prompt execution**
   - Empty prompts return a per-section "Prompt is empty" message.
   - Results are shown per function in the popup.
   - Translation is included as the first built-in function.

4. **Streaming**
   - When enabled, each function streams independently.
   - The popup updates each section in real time.

## Related Strings

- `Sources/digger/UIStrings.swift`
  - Added UI strings for custom function labels, placeholders, and popup messages.
  - Updated copy label to cover multi-result output.
