import AppKit
import Testing
@testable import digger

@MainActor
struct PopupSizingTests {
    @Test func shortSelectionsAreCompactAndLongSelectionsUseAvailableWidth() {
        #expect(PopupSizing.preferredWidth(source: "Hello 世界", fontSize: 14, maximum: 640) == 360)
        #expect(PopupSizing.preferredWidth(source: String(repeating: "Long paragraph. ", count: 200), fontSize: 14, maximum: 640) == 640)
        #expect(PopupSizing.preferredWidth(source: "```swift\nlet x = 0\n```", fontSize: 14, maximum: 520) == 520)
    }

    @Test func fittingPreservesAnchorAndCapsToScreenOnEveryDisplay() {
        for screen in [CGRect(x: 0, y: 24, width: 1440, height: 876),
                       CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                       CGRect(x: 0, y: 900, width: 1024, height: 744)] {
            for edge in [PopupSizing.GrowthEdge.top, .bottom] {
                let frame = CGRect(x: screen.minX + 30, y: screen.midY, width: 400, height: 120)
                let result = PopupSizing.fittedFrame(current: frame, contentHeight: 2000, maximumHeight: 600,
                                                     screen: screen, edge: edge, growOnly: false)
                #expect(screen.contains(result))
                #expect(result.height <= 600)
                #expect(result.width == frame.width)
                #expect(edge == .top ? result.maxY == frame.maxY : result.minY == frame.minY)
            }
        }
    }

    @Test func streamingOnlyGrowsUntilAnExplicitCollapseOrCompletion() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let current = CGRect(x: 20, y: 300, width: 400, height: 400)
        let live = PopupSizing.fittedFrame(current: current, contentHeight: 130, maximumHeight: 600,
                                          screen: screen, edge: .top, growOnly: true)
        let complete = PopupSizing.fittedFrame(current: current, contentHeight: 130, maximumHeight: 600,
                                              screen: screen, edge: .top, growOnly: false)
        #expect(live == current)
        #expect(complete.height == 130 && complete.maxY == current.maxY)
        #expect(PopupSizing.growthEdge(near: CGPoint(x: 30, y: 50), screen: screen) == .bottom)
        #expect(PopupSizing.growthEdge(near: CGPoint(x: 30, y: 750), screen: screen) == .top)
    }
}
