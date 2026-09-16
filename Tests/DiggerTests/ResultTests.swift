import AppKit
import Testing
@testable import digger

@MainActor
struct ResultTests {
    let function = PopupFunction(id: UUID(), title: "Translate", prompt: "Translate", isTranslation: false)

    @Test func staleRequestCannotOverwriteNewSelection() {
        let model = ResultModel()
        let old = UUID(), current = UUID()
        model.begin(original: "old", requestID: old, functions: [function])
        model.begin(original: "new", requestID: current, functions: [function])
        model.update("late reply", requestID: old, functionID: function.id, phase: .complete)
        #expect(model.original == "new")
        #expect(model.sections[0].text.isEmpty)
        model.update("new reply", requestID: current, functionID: function.id, phase: .complete)
        #expect(model.sections[0].text == "new reply")
    }

    @Test func stopPreservesPartialAndCompletedWork() {
        let model = ResultModel(), id = UUID()
        let second = PopupFunction(id: UUID(), title: "Summary", prompt: "Summarize", isTranslation: false)
        model.begin(original: "source", requestID: id, functions: [function, second])
        model.update("partial", requestID: id, functionID: function.id, phase: .streaming)
        model.update("finished", requestID: id, functionID: second.id, phase: .complete, cached: true)
        model.stop()
        model.update("late", requestID: id, functionID: function.id, phase: .complete)
        #expect(model.sections[0].text == "partial")
        #expect(model.sections[0].phase == .stopped)
        #expect(model.sections[1].phase == .complete)
        #expect(model.sections[1].cached)
        #expect(!model.running)
        #expect(model.combinedText(includeOriginal: true) == "source\n\nTranslate\npartial\n\nSummary\nfinished")
    }

    @Test func retryResetsStoppedSectionsAndEmptyActionsAreIdle() {
        let model = ResultModel()
        model.begin(original: "first", requestID: UUID(), functions: [function])
        model.stop()
        model.begin(original: "retry", requestID: UUID(), functions: [function])
        #expect(model.running)
        #expect(model.sections[0].text.isEmpty)
        model.begin(original: "empty", requestID: UUID(), functions: [])
        #expect(!model.running)
    }

    @Test func windowStaysOnEachDisplay() {
        let screens = [CGRect(x: 0, y: 24, width: 1440, height: 876),
                       CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                       CGRect(x: 0, y: 900, width: 1024, height: 744)]
        for screen in screens {
            for point in [screen.origin, CGPoint(x: screen.maxX, y: screen.maxY), CGPoint(x: screen.midX, y: screen.midY)] {
                let frame = SelectionPopup.frame(size: CGSize(width: 640, height: 620), near: point, visibleFrame: screen)
                #expect(screen.contains(frame))
            }
        }
        let tiny = CGRect(x: -200, y: 300, width: 300, height: 200)
        #expect(SelectionPopup.frame(size: CGSize(width: 640, height: 620), near: .zero, visibleFrame: tiny) == tiny)
    }
}
