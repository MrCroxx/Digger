import MarkdownUI
import SwiftUI

/// Native GFM rendering. The model parses each published stream snapshot once;
/// pinning, copying, or updates to another action do not reparse unchanged text.
struct MarkdownContent: View, @MainActor Equatable {
    let content: MarkdownUI.MarkdownContent
    let fontSize: CGFloat

    var body: some View {
        Markdown(content)
            .markdownTheme(Self.compactTheme)
            .markdownTextStyle {
                FontSize(fontSize)
                ForegroundColor(DiggerTheme.ink)
            }
            .markdownSoftBreakMode(.lineBreak)
            .markdownImageProvider(PopupImagePlaceholder())
            .markdownInlineImageProvider(PopupInlineImagePlaceholder())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let compactTheme = Theme.basic
        .link { ForegroundColor(DiggerTheme.accent) }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.94))
            BackgroundColor(DiggerTheme.canvas)
        }
        .heading1 { heading($0, scale: 1.3) }
        .heading2 { heading($0, scale: 1.2) }
        .heading3 { heading($0, scale: 1.1) }
        .heading4 { heading($0, scale: 1) }
        .heading5 { heading($0, scale: 1) }
        .heading6 { heading($0, scale: 1) }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label.markdownMargin(top: 2, bottom: 2)
        }
        .blockquote { configuration in
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(DiggerTheme.accent).frame(width: 3)
                configuration.label.markdownTextStyle { ForegroundColor(DiggerTheme.muted) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 0, bottom: 8)
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 4) {
                if let language = configuration.language, !language.isEmpty {
                    Text(language).font(.system(size: 10)).foregroundStyle(DiggerTheme.muted)
                        .padding(.horizontal, 8).padding(.top, 6)
                }
                ScrollView(.horizontal) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.94))
                            BackgroundColor(nil)
                        }
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(8)
                        .background(PopupScrollStyle())
                }
            }
            .background(DiggerTheme.canvas, in: RoundedRectangle(cornerRadius: 6))
            .markdownMargin(top: 0, bottom: 8)
        }
        .table { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: DiggerTheme.line))
                    .markdownTableBackgroundStyle(.alternatingRows(DiggerTheme.paper, DiggerTheme.canvas))
                    .background(PopupScrollStyle())
            }
            .markdownMargin(top: 0, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 { FontWeight(.semibold) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.vertical, 5)
        }
        .thematicBreak {
            Rectangle().fill(DiggerTheme.line).frame(height: 1)
                .markdownMargin(top: 8, bottom: 8)
        }

    private static func heading(_ configuration: BlockConfiguration, scale: CGFloat) -> some View {
        configuration.label
            .markdownTextStyle { FontWeight(.semibold); FontSize(.em(scale)) }
            .markdownMargin(top: 8, bottom: 6)
    }
}

/// Each top-level block has a stable slot and owns its spacing. MarkdownUI's
/// content-hashed internal sequence can no longer reset the gaps above the tail.
struct StreamingMarkdownContent: View {
    let blocks: [PopupMarkdown.Block]
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                MarkdownContent(content: block.content, fontSize: fontSize).equatable()
                    #if DEBUG
                    .background(StreamBlockProbe(index: block.id))
                    #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transaction { $0.animation = nil }
    }
}

#if DEBUG
private struct StreamBlockProbe: NSViewRepresentable {
    let index: Int
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("stream-block-\(index)")
    }
}
#endif

// Preserve the existing local rendering behavior: image references remain in copied
// Markdown, but displaying a selection never fetches external images in the background.
private struct PopupImagePlaceholder: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Label(localized("Image", "图片", "画像"), systemImage: "photo")
            .font(.system(size: 12)).foregroundStyle(DiggerTheme.muted)
            .help(url?.absoluteString ?? "")
    }
}

private struct PopupInlineImagePlaceholder: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        Image(systemName: "photo")
    }
}
