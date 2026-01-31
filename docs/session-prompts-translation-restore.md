# Prompts Translation Edits and Restore

## Goals
- Make translation a normal custom prompt that can be edited or deleted.
- Remove the target-language setting and rely on prompt text instead.
- Add a one-click way to restore the default prompts.
- Update the default translation prompt to support Simplified Chinese <-> English.
- Prevent Advanced tab labels from truncating long variable names.

## Key Changes

### Translation Prompt Defaults
- Updated the default translation prompt to:
  "Translate the user's text between Simplified Chinese and English. Preserve meaning, formatting, and proper nouns."
- Kept defaults centralized in `PromptTemplates` and referenced in `AppPreferences.defaultCustomFunctions`.

Files:
- `Sources/digger/Translation/PromptTemplates.swift`
- `Sources/digger/Preferences/AppPreferences.swift`

### Custom Prompts as the Single Source of Truth
- Removed special handling for translation prompts (no fixed ID, no forced insertion, no delete restriction).
- `PopupFunction.availableFunctions()` now renders exactly the custom prompt list.
- Translation runs in the popup are just one of the prompts; no hidden prompt injection.

Files:
- `Sources/digger/Selection/PopupFunction.swift`
- `Sources/digger/Preferences/PreferencesView.swift`

### Restore Prompts Button
- Added a bottom-left "Restore Prompts" button on the Prompts tab.
- Restores the current prompt list to `AppPreferences.defaultCustomFunctions` (Translation + Summary).
- Added localized strings for the button label.

Files:
- `Sources/digger/Preferences/PreferencesView.swift`
- `Sources/digger/UIStrings.swift`

### Target Language Removal
- Removed the target-language preference and any logic tied to it.
- Translation behavior is now entirely controlled by the prompt text.

Files:
- `Sources/digger/Preferences/PreferencesView.swift`
- `Sources/digger/Preferences/PreferencesViewModel.swift`
- `Sources/digger/UIStrings.swift`

### Advanced Tab Label Wrapping
- Long variable names in Advanced now wrap across two lines to avoid truncation.

Files:
- `Sources/digger/Preferences/PreferencesView.swift`

## Implementation Notes
- Defaults live in `AppPreferences.defaultCustomFunctions` and are reused by the restore button to keep behavior consistent.
- `OpenAITranslator.translate()` now uses the default translation prompt for any direct translation call sites; popup execution uses the prompt list from preferences.
- No schema migration is required; existing user prompt lists remain intact until restored manually.
