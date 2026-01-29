# Prompts Parallelism and Streaming UX

## Goals
- Restore parallel prompt execution in the force-click flow.
- Keep prompt text legible without changing the default text color configuration.
- Add table column headers for prompt title and prompt text.
- Rename “Custom Functions” to “Custom Prompts” with updated i18n strings.
- Improve streaming smoothness while keeping throughput fast.

## Key Changes

### Preferences UI
- Added prompt table headers using existing i18n labels (Title / Prompt).
- Renamed “Custom Functions” to “Custom Prompts” in all supported languages.
- Updated input backgrounds to use system text background color for contrast without changing the default text color.

Files:
- `Sources/digger/Preferences/PreferencesView.swift`
- `Sources/digger/UIStrings.swift`

### Parallel Prompt Execution
- Each prompt now creates its own `OpenAITranslator`, avoiding actor serialization and allowing true parallel requests.
- Added a lightweight `PopupAnchor` wrapper to pass the popup location safely across async boundaries.

Files:
- `Sources/digger/Selection/ForceClickSelectionHandler.swift`

### Streaming Output Flow Control
- Replaced per-character chunking with time-based batching.
- Added a minimum flush size to avoid overly small updates that slow down total completion time.
- Tuned to a 20ms update interval and a 48-character minimum flush for smoother but faster output.

Files:
- `Sources/digger/Selection/ForceClickSelectionHandler.swift`

### Concurrency Safety
- `PopupFunction` is now `Sendable` to satisfy concurrency requirements.
- `ForceClickSelectionHandler` is marked `@unchecked Sendable` to allow async use from event handlers.
- Event tap now triggers async work via `Task` with a safe local capture.

Files:
- `Sources/digger/Selection/PopupFunction.swift`
- `Sources/digger/Selection/ForceClickSelectionHandler.swift`
- `Sources/digger/EventTap/EventTap.swift`
- `Sources/digger/App/Digger.swift`

## Notes
- Streaming remains conditional on the existing “Stream Translation” preference.
- Output still finalizes with a trimmed result to avoid trailing whitespace.
