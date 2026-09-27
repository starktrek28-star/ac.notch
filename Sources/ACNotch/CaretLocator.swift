import AppKit
import ApplicationServices

/// Finds the blinking text cursor on screen through the Accessibility API.
enum CaretLocator {
    /// Chromium browsers only report caret positions once asked to expose full accessibility.
    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]
    private static var wokenPIDs = Set<pid_t>()

    /// The caret's rectangle in Cocoa screen coordinates (origin bottom-left), or nil if
    /// the focused app doesn't say. Falls back to the text field's frame for small fields.
    static func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard let focused = element(system, kAXFocusedUIElementAttribute) else { return nil }

        if let rect = selectionBounds(focused) ?? webCaretBounds(focused) { return toCocoa(rect) }

        wakeAccessibility(for: focused)
        if let field = frame(of: focused), field.height > 0, field.height < 200 { return toCocoa(field) }
        return nil
    }

    private static func selectionBounds(_ element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return nil }

        if let rect = bounds(element, CFRange(location: selection.location, length: 0)), rect.height > 0 {
            return CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 1), height: rect.height)
        }
        // Some apps give nothing for an empty range: use the character before the caret instead.
        if selection.location > 0,
           let rect = bounds(element, CFRange(location: selection.location - 1, length: 1)), rect.height > 0 {
            return CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
        }
        return nil
    }

    /// Web pages (Safari, Chrome and other browsers) describe text positions with "text
    /// markers" rather than character ranges. Measure the character just before the caret.
    private static func webCaretBounds(_ element: AXUIElement) -> CGRect? {
        var selectionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &selectionRef) == .success,
              let selection = selectionRef else { return nil }

        if let rect = markerRangeBounds(element, selection), rect.height > 0 {
            return CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
        }
        // An empty selection often measures as nothing: widen it to the previous character.
        guard let caret = parameterized(element, "AXStartTextMarkerForTextMarkerRange", selection),
              let previous = parameterized(element, "AXPreviousTextMarkerForTextMarker", caret),
              let range = parameterized(element, "AXTextMarkerRangeForUnorderedTextMarkers", [previous, caret] as CFArray),
              let rect = markerRangeBounds(element, range), rect.height > 0 else { return nil }
        return CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
    }

    private static func markerRangeBounds(_ element: AXUIElement, _ markerRange: CFTypeRef) -> CGRect? {
        guard let boundsRef = parameterized(element, "AXBoundsForTextMarkerRange", markerRange),
              CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.height < 400 else { return nil }
        return rect
    }

    private static func parameterized(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &result) == .success
        else { return nil }
        return result
    }

    private static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rangeValue, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.height < 400 else { return nil }
        return rect
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    /// Chrome and Electron apps (Slack, Discord, VS Code…) keep their accessibility tree
    /// asleep until a client asks. Ask once per app so the next lookup can find the caret.
    private static func wakeAccessibility(for element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, !wokenPIDs.contains(pid) else { return }
        wokenPIDs.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, chromiumBrowsers.contains(id) {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    /// Accessibility uses a top-left origin on the main display; AppKit uses bottom-left.
    private static func toCocoa(_ rect: CGRect) -> NSRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
