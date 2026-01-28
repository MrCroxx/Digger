import ApplicationServices
import Foundation

func findSelectedText(
    in element: AXUIElement,
    maxDepth: Int,
    remainingNodes: inout Int
) -> String? {
    if remainingNodes <= 0 {
        return nil
    }
    remainingNodes -= 1

    if let selectedText = copyAttribute(
        element: element,
        attribute: kAXSelectedTextAttribute as CFString
    ) as? String, !selectedText.isEmpty {
        return selectedText
    }

    if maxDepth == 0 {
        return nil
    }

    guard let children = copyAttribute(
        element: element,
        attribute: kAXChildrenAttribute as CFString
    ) as? [AXUIElement] else {
        return nil
    }

    for child in children {
        if let selectedText = findSelectedText(
            in: child,
            maxDepth: maxDepth - 1,
            remainingNodes: &remainingNodes
        ) {
            return selectedText
        }
    }

    return nil
}

func copyAttribute(element: AXUIElement, attribute: CFString) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard result == .success else {
        return nil
    }
    return value
}

func copyParameterizedAttribute(
    element: AXUIElement,
    attribute: CFString,
    parameter: AXValue
) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value)
    guard result == .success else {
        return nil
    }
    return value
}

func currentWordRange(in text: String, caretIndex: Int) -> CFRange {
    let cfText = text as CFString
    let length = CFStringGetLength(cfText)
    if length == 0 {
        return CFRange(location: 0, length: 0)
    }

    let clampedIndex = max(0, min(caretIndex, length))
    let locale = Locale.current as CFLocale
    let tokenizer = CFStringTokenizerCreate(
        kCFAllocatorDefault,
        cfText,
        CFRange(location: 0, length: length),
        kCFStringTokenizerUnitWord,
        locale
    )

    CFStringTokenizerGoToTokenAtIndex(tokenizer, clampedIndex)
    var range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
    if range.location == kCFNotFound || range.length == 0, clampedIndex > 0 {
        CFStringTokenizerGoToTokenAtIndex(tokenizer, clampedIndex - 1)
        range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
    }

    if range.location == kCFNotFound || range.length == 0 {
        return CFRange(location: clampedIndex, length: 0)
    }

    return range
}
