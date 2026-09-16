import ApplicationServices
import AppKit
import Foundation

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        }
    }

    func restore(to pasteboard: NSPasteboard, ifUnchangedSince changeCount: Int? = nil) {
        if let changeCount, pasteboard.changeCount != changeCount { return }
        pasteboard.clearContents()
        let restoredItems = items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

/// Browsers can advertise either public.html or a WebKit web archive.
/// Only the archive's main HTML resource is decoded; subresources are never loaded.
struct SelectionClipboardContent {
    let plainText: String?
    let html: String?

    init(pasteboard: NSPasteboard) {
        plainText = pasteboard.string(forType: .string)
        if let direct = pasteboard.string(forType: .html), !direct.isEmpty {
            html = direct
            return
        }
        html = ["Apple Web Archive pasteboard type", "com.apple.webarchive"].lazy.compactMap { type -> String? in
            guard let data = pasteboard.data(forType: .init(type)),
                  let archive = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let resource = archive["WebMainResource"] as? [String: Any],
                  let mime = resource["WebResourceMIMEType"] as? String, mime.lowercased().contains("html"),
                  let bytes = resource["WebResourceData"] as? Data else { return nil }
            var encoding = String.Encoding.utf8
            if let charset = resource["WebResourceTextEncodingName"] as? String {
                let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
                if cfEncoding != kCFStringEncodingInvalidId {
                    encoding = .init(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                }
            }
            return String(data: bytes, encoding: encoding)
        }.first
    }
}
