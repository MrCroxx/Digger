# Streaming result rendering

The interaction aims for the smooth, progressively formatted reading experience of a
chat app. This is an independent native implementation, not a port of ChatGPT's
private UI. OpenAI's public [streaming guide](https://developers.openai.com/api/docs/guides/streaming-responses)
documents the event transport; it does not establish the app's rendering internals.
[Streamdown's streaming features](https://github.com/vercel/streamdown/blob/main/skills/streamdown/references/features.md)
and [2.5 release notes](https://vercel.com/changelog/streamdown-2-5) describe useful
public precedents: incomplete Markdown repair, individually memoized blocks, and
staggered presentation.

## Pipeline

- The runner forwards every accumulated network snapshot. Previously, a chunk inside
  the 50 ms throttle window could remain invisible until another network event.
- `ResultModel.receive` retains the exact received text for copying and feeds a
  per-action `StreamingText` buffer. A shared 33 ms task reveals grapheme clusters,
  accelerates through bursts, and goes idle after catching up. Completion drains
  the buffer; cache hits and non-streamed responses appear immediately.
- `StreamingMarkdown` repairs only the display source while generating: unfinished
  emphasis and code spans receive temporary closing markers; an unfinished link
  shows its label; an ambiguous pipe-table header waits for a delimiter row. Fenced
  and indented code remain literal. Completion and stop render the exact source.
- cmark parses the document at each changed display frame, preserving GFM and late
  reference-link resolution. `PopupMarkdown.blocks` reuses unchanged MarkdownUI
  content by rendered semantics. Only changed blocks rebuild MarkdownUI values.
- `StreamingMarkdownContent` owns stable block slots and fixed inter-block spacing.
  This avoids MarkdownUI's content-hashed block sequence discarding the preceding
  margin measurement every time the active block grows. There is no renderer swap
  when generation ends.
- The outer native scroll view follows growth only while the reader is at the
  bottom. Scrolling up preserves the reading position; returning to the bottom
  resumes following. Window width and height remain user-controlled.

Copying, cache storage, stale-request checks, and stop/retry never use repaired text.
No web runtime, remote images, or new package dependencies are needed.

## Verification

```sh
/usr/bin/python3 scripts/test-transport.py
/usr/bin/python3 scripts/test-popup-layout.py
```

The first command runs the Swift tests plus loopback transport/cache/cancellation
checks. The second opens real native preview windows in three configurations and
checks stable block positions, follow/pause/resume scrolling, horizontal overflow,
final buffer draining, fixed window geometry, and user resizing. Both use synthetic
content and do not call a provider. The preview can also be watched with:

```sh
swift run digger --preview --markdown-stream
```

Incomplete Markdown is inherently ambiguous. A later table delimiter, reference
definition, or final literal punctuation can still legitimately change the active
block's formatting. We retain the native MarkdownUI renderer, including its nested
list/table layout, rather than claiming pixel-identical behavior to ChatGPT.
