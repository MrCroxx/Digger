import AppKit

/// Geometry policy kept independent of SwiftUI's transient intrinsic size.
enum PopupSizing {
    enum GrowthEdge { case top, bottom }
    static let minimum = CGSize(width: 360, height: 120)

    static func preferredWidth(source: String, fontSize: CGFloat, maximum: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        // Bound the measurement work for large selections. Estimate a comfortable
        // reading aspect ratio instead of stretching to the longest prose line.
        let sample = String(source.prefix(4_000))
        let extent = (sample.replacingOccurrences(of: "\n", with: " ") as NSString)
            .size(withAttributes: [.font: font]).width
        let readingWidth = ceil(sqrt(extent * (fontSize * 1.4) * 2.8) + 24)
        let structured = sample.contains("```") || sample.contains("| ---") || sample.contains("| :---")
        return min(maximum, max(minimum.width, structured ? maximum : readingWidth))
    }

    static func growthEdge(near point: CGPoint, screen: CGRect) -> GrowthEdge {
        point.y - screen.minY >= screen.maxY - point.y ? .top : .bottom
    }

    static func fittedFrame(current: CGRect, contentHeight: CGFloat, maximumHeight: CGFloat,
                            screen: CGRect, edge: GrowthEdge, growOnly: Bool) -> CGRect {
        let available = edge == .top ? current.maxY - screen.minY : screen.maxY - current.minY
        let limit = max(1, min(maximumHeight, screen.height * 0.85, available))
        let wanted = min(limit, max(minimum.height, ceil(contentHeight)))
        let height = growOnly ? min(limit, max(current.height, wanted)) : wanted
        let width = min(current.width, screen.width)
        return CGRect(x: min(max(current.minX, screen.minX), screen.maxX - width),
                      y: edge == .top ? max(screen.minY, current.maxY - height) : max(screen.minY, current.minY),
                      width: width, height: height)
    }
}
