# README screenshots

The English and Chinese READMEs use native screenshots rendered from the
current checkout by [capture-readme.py](../../scripts/capture-readme.py).
They are not generated illustrations or composited desktop mockups.

## Reproduce

On macOS with the project's Swift toolchain:

```bash
python3 scripts/capture-readme.py
```

The script builds Debug once, then runs each scene sequentially. It renders
the app's actual AppKit/SwiftUI content views as PNGs with a two-second settling
delay, without capturing the surrounding desktop or system title bar.

| Files (`en` / `zh`) | Scene |
| --- | --- |
| `popup-*.png` | Expanded source, translation, and key points |
| `markdown-*.png` | Explanation with a table, wrapped code, and a quote |
| `dark-*.png` | The reading popup in dark appearance |
| `prompts-*.png` | Shared system prompt and three example actions |
| `appearance-*.png` | Typography, opacity, shortcut, and automatic sizing |
| `provider-*.png` | Public default endpoint, empty key, and default model |

English captures use `--english`; Chinese uses preview mode's default language.
Light appearance is explicit; the dark scene overrides it with `--dark`.
The popup uses automatic sizing with 700 × 760 pt limits and an expanded source.
Settings captures use a 980 × 760 pt content area. These are demonstration
preferences, not a change to the app's defaults.

For a single scene:

```bash
swift run digger --preview --showcase --english --light \
  --render /tmp/digger-popup.png --render-delay 2
swift run digger --preview --showcase --english --light \
  --settings --settings-tab functions \
  --render /tmp/digger-prompts.png --render-delay 2
```

Supported settings tab identifiers are `general`, `popup`, `functions`,
`api`, and `cache`. Add `--showcase-code` for the formatted explanation.

## Sample content and privacy

[PreviewShowcase.swift](../../Sources/digger/App/PreviewShowcase.swift) contains
originally authored English and Chinese examples about caching. They illustrate
the interface, not an actual provider run or a performance measurement.
Translation and Key points are enabled in the sample settings; Explain is an
additional example action shown separately in the Markdown scene.

Preview mode clears and uses only `com.mrcroxx.digger.preview.preferences`.
It does not read the normal app's API settings, send requests, change login-item
registration, or register the global shortcut. The API key field stays empty;
only the public default endpoint and model are shown. No credentials need
redaction after capture.

## Earlier images

The older `native-*.png` and `digger-*.png` images remain as historical assets
for earlier documentation. The current product READMEs use only the bilingual
captures listed above. Regenerate and visually inspect both languages after
changing the UI or fixtures.
