# Native redesign

## Decision

Keep macOS 13+ support and use SwiftUI for the interface, with AppKit for the menu bar, floating panel, keyboard events and Accessibility integration. Digger's essential job is to work with text in other Mac apps. Those integrations remain native, while the presentation and request lifecycle have been rewritten.

Digger is a transient reading utility. Its popup uses a single 34 pt toolbar, flat text sections, thin dividers and 12 pt outer margins. There is no logo header, result card padding or bottom status bar. The original is a one-line disclosure in the toolbar, collapsed by default; existing collapse choices are retained. Controls remain available through labeled icon buttons and keyboard shortcuts. Adaptive paper colors and brown accents support light and dark appearances.

| Direction | Fit for Digger | Decision |
| --- | --- | --- |
| SwiftUI + AppKit | Native text selection, focus, shortcuts, menu bar and floating windows; custom layout and adaptive colors | Implemented |
| Electron | Excellent web layout and reusable CSS, but introduces Chromium/Node processes and still needs platform integration for reading selections | Useful if cross-platform support becomes a goal; unnecessary for this Mac-only rewrite |
| Swift + WKWebView | Keeps the native shell with HTML rendering | A possible future renderer for complex tables/math; introduces a web/native bridge and is not necessary for the present text workflows |

This is a fit assessment, not a measured Electron memory/latency comparison. Sources: [Apple NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview), [Apple NSPanel](https://developer.apple.com/documentation/appkit/nspanel), [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [Apple WebKit](https://developer.apple.com/documentation/webkit/webkit-for-appkit-and-uikit).

## What changed

- Replaced the 1,702-line manually measured AppKit popup with a SwiftUI result view, a small AppKit window controller, and an independently testable result model.
- Streaming updates are coalesced to at most 20 updates/second. Window geometry remains fixed while content grows inside a scroll view. User resizing and dragging still work.
- Each action has waiting, streaming, completed, failed and stopped states. Stop/dismiss/retry/new selection cancel the active generation and propagate cancellation through the SDK to its network request. Partial results remain visible on Stop. Request IDs reject late results.
- Added pinning, native Markdown inline formatting, headings, quotes and literal fenced code blocks. Copy a section, all results, or the original. `⌘⇧C` copies all results; `⌘⌥C` includes the original; ordinary `⌘C` remains native selection copy.
- Settings use a scrollable sidebar layout with shared card styles and readable field labels. The popup page previews typography. Prompt editors retain native text editing and multiline input.
- Welcome retains its two-column layout, serif headings, warm brown sidebar and separate setup cards. Copy is limited to one short headline, permission and API explanations, shortcut and startup options. Extra slogans and repeated status text were removed from welcome and settings; typography previews use neutral sample text.
- Popup scrollbars use a 4 pt rounded overlay thumb without a track, including horizontal code/table scrolling. Native hit areas, dragging and fade animations are retained; system scrollbar preferences are unchanged.
- Each prompt has an automatically saved enable switch. Only enabled prompts create result sections or run requests on the next selection/retry. Translation starts enabled and Summary disabled, including legacy built-in Summary entries without a saved switch. Explicit choices and prompt content are retained. All prompts can be disabled; the popup then links back to Settings.
- Removed Force Touch, its pressure/suppression state machine, the multitouch package and framework bundling. Global hotkeys use RegisterEventHotKey, while NSEvent mouse monitors only handle outside dismissal. Mouse events are never suppressed and double-clicks are never synthesized.
- Preserved existing preference keys, API credentials, prompts and cache format. Removed the old settings initializer that cleared custom prompts. Obsolete Force Touch defaults on disk are simply ignored.
- API requests snapshot endpoint/model/prompt/effort together so edits cannot mix providers and cache identities midway through a generation. Endpoint validation now rejects malformed URLs, normalizes trailing slashes, and uses port 80 for HTTP when unspecified.
- Removed logging of selections and generated answers. The API SDK is pinned to the previously resolved revision for reproducible builds.
- Fixed welcome permission polling when reopening the window. Welcome can be closed even before granting permission.

## Intentional interaction changes

- Activation uses the global keyboard shortcut (default `⌘E`). There is no Force Touch compatibility or trackpad setup step.
- The popup uses a stable reading area rather than growing/shrinking for every incoming token. Existing width/height settings are honored with a 360×280 usable minimum and screen bounds. New defaults are 520×420 and 14 pt; saved preferences remain intact.
- Tooltips use native macOS timing instead of a custom floating-tooltip timer. Its old delay preference is ignored.
- Native [MarkdownUI 2.4.1](https://github.com/gonzalezreal/swift-markdown-ui/tree/2.4.1) replaces the ad-hoc Markdown splitter. Streaming snapshots render headings, nested/task lists, tables, quotes, links, emphasis and fenced code. Parsed content is retained per action; ordinary UI changes do not reparse it. Tables and code can scroll horizontally inside a narrow popup. Images use local placeholders; raw HTML is not executed, and math remains source text.
- Browser selections prefer a temporary rich clipboard copy over flattened Accessibility text. HTML and WebKit web-archive clipboard flavors are supported. Copied HTML is converted locally to Markdown with SwiftSoup, preserving list nesting/numbering, anchors, code, headings, quotes and tables. Clipboard fragment markers exclude unselected page text while retaining ancestor structure. The previous clipboard is restored unless a newer change was observed. Editors continue using verbatim Accessibility selections; plain text remains the browser fallback.
- Markdown input receives an output-format instruction for both built-in and saved custom prompts. Translation preserves document structure and code/link destinations. The effective instruction participates in cache identity. Input, results, cache entries and copy actions preserve Markdown whitespace verbatim (including indented code and hard breaks).

## Validation

- `swift build`
- `swift test`: state isolation, stop/retry, text copying, multi-display geometry, Markdown and endpoint validation.
- `/usr/bin/python3 scripts/test-transport.py`: all tests plus a temporary loopback HTTP server. Covers non-streaming/streaming output, disk cache, HTTP errors, reasoning request payloads, network disconnect on cancellation, and no partial cache writes. Uses fixture text and a fake key, never a real provider.
- Real native-window review using the debug-only isolated preview: popup, settings navigation, API page, prompt sheet, collapse/expand; rendered light/dark and welcome artifacts.
- `CREATE_DMG=0 ./scripts/build-app.sh` creates `dist/Digger.app`.
- CI also creates a DMG using `hdiutil` without Finder automation. Signing and optional app notarization happen before the app enters the image. `scripts/verify-dmg.sh` verifies the checksum, mounts the image read-only, checks the contained app signature and confirms the Applications shortcut before upload.

The available machine has no valid Apple signing identity. The local build can be ad-hoc signed, but it is not notarized. A stable Apple signing identity remains necessary to avoid Accessibility identity changes across rebuilds. Full selection/shortcut behavior in third-party apps still depends on granting this build Accessibility access; no new system permission was granted during automated validation.

## Offline UI preview

```sh
swift run digger --preview
swift run digger --preview --settings
swift run digger --preview --welcome
swift run digger --preview --dark
swift run digger --preview --small
swift run digger --preview --markdown
swift run digger --preview --html Tests/DiggerTests/Fixtures/toc.html
swift run digger --preview --markdown-stream --render-delay 4 --render /tmp/digger-markdown.png
swift run digger --preview --small --expanded
swift run digger --preview --english
swift run digger --preview --render /tmp/digger-popup.png
```

Preview mode exists only in debug builds. It uses an isolated preference suite, synthetic results, no event tap, and no API requests. `--render` renders the app's own content view to a PNG and exits. Use `--small` for the 360×280 minimum, `--expanded` for visible source text, `--long` for long content at the largest font size, and `--loading` / `--error` for request states. `--japanese`, `--dark`, `--settings` and `--welcome` can be combined.

## Global shortcut diagnosis

The global hotkey is registered independently of Accessibility permission. When the configured hotkey is received without permission, the popup explains how to enable access. If selection extraction returns no text, it shows a notice instead of silently returning. Logs contain stage names, not selected text or API keys.

The menu bar shows the binding and registration/permission status. Re-recording a shortcut temporarily unregisters it, then registers the new binding; leaving the settings window also ends recording so the hotkey cannot remain suspended.

```sh
swift run digger --diagnose
```

This debug-only command prints the effective binding, registration result, Accessibility status and executable path, then unregisters and exits without sending API requests. Stop another running Digger first, since hotkeys are registered exclusively. Run it from the same terminal used to launch Digger so its permission context matches.
