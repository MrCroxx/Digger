# Welcome Page Lookup Tips and First-Launch Logic

## Overview
This session updated the welcome flow to:
- add a non-blocking tip for disabling "Look Up & Data Detectors",
- increase the welcome window size so each tip sentence fits on a single line,
- and skip the welcome screen on non-first launches when required permissions are already granted.

The Look Up & Data Detectors state is not reliably readable from macOS defaults on the target machines, so the UI presents a guidance tip instead of a status check.

## Key Changes

### 1) Tip row for Look Up & Data Detectors
The previous detection logic was removed. The welcome page now shows a tips-only row with an info icon and a "Open Trackpad Settings" action. This keeps the guidance visible without blocking the user or showing a misleading status.

Files:
- `Sources/digger/Welcome/WelcomeView.swift`
- `Sources/digger/UIStrings.swift`

Implementation details:
- Added `TipRow` component that mirrors the layout of permission rows but always uses a neutral info icon.
- Updated Look Up & Data Detectors copy to two short sentences, with an explicit line break in localized strings.
- Removed any dependency on permission status values for this row.

### 2) Welcome window sizing and text layout
To ensure each sentence in the tips is displayed on a single line, the window minimum size was increased. The description text now allows up to two lines and preserves explicit line breaks.

File:
- `Sources/digger/Welcome/WelcomeView.swift`

Implementation details:
- Increased the window minimum size: `.frame(minWidth: 760, minHeight: 440)`.
- Added `.lineLimit(2)` and `.fixedSize(horizontal: false, vertical: true)` to description texts in both permission and tip rows.

### 3) Skip welcome after first launch when permissions are ready
The welcome page should not show on non-first launches if all required permissions are already granted. This is now handled by a new preference flag.

Files:
- `Sources/digger/Preferences/AppPreferences.swift`
- `Sources/digger/App/Digger.swift`

Implementation details:
- Added `HasLaunchedBefore` flag with `hasLaunchedBefore()` and `setHasLaunchedBefore(_:)`.
- On app startup, we mark the app as launched and show the welcome only if:
  - it is the first launch, or
  - permissions are missing (`PermissionChecker.needsAttention()`)

## Strings Updated
Look Up & Data Detectors guidance is now two sentences with a newline in each language:
- English: "Turn off Look Up & Data Detectors in Trackpad settings.\nIt helps avoid conflicts with Digger."
- Chinese: "请在触控板设置中关闭“查询与数据检测器”。\n这样可以避免与 Digger 冲突。"
- Japanese: "トラックパッド設定で「調べる & データ検出」をオフにしてください。\nDigger との競合を避けるためです。"

## Notes
- The Look Up & Data Detectors setting could not be reliably read from defaults on target machines, so no detection is performed.
- The welcome page continues to block start only on required permissions (Accessibility).
