# Session Notes: Prompts Tab and Global System Prompt

This document summarizes the Prompts-related changes in this session, including the new global system prompt and how it is applied.

## Overview

- Preferences tab label changed from "Functions" to "Prompts" (localized in all supported languages).
- Added a global system prompt field in Preferences that is editable and persisted.
- The global system prompt is sent with every prompt, including translation.
- Default system prompt text: "Only return the result, without extra output."

## Preferences UI

- `Sources/digger/Preferences/PreferencesView.swift`
  - Prompts tab now contains a system prompt field above the custom prompt list.
  - The field is a standard text input and is saved on change.

- `Sources/digger/Preferences/PreferencesViewModel.swift`
  - Adds `systemPrompt` binding for the Preferences UI.

## Persistence

- `Sources/digger/Preferences/AppPreferences.swift`
  - Stores the global system prompt in `UserDefaults` under `SystemPrompt`.
  - Empty values clear the stored entry, falling back to the default text.

## Prompt Application

- `Sources/digger/Translation/OpenAITranslator.swift`
  - Prepends the system prompt as a `system` message before each per-function prompt.
  - Applies to translation and all custom prompts.

## Strings

- `Sources/digger/UIStrings.swift`
  - Adds localized strings for the Prompts tab label and the system prompt field (title, description, placeholder).
