import ApplicationServices

/// Uses the Accessibility API to peek at the character before the text cursor.
enum AXProbe {
    /// true: cursor is at the start of a word. false: it's in the middle of one.
    /// nil: the app doesn't say.
    static func cursorIsAtWordStart() -> Bool? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return nil }
        if selection.location <= 0 { return true }

        var previous = CFRange(location: selection.location - 1, length: 1)
        guard let previousValue = AXValueCreate(.cfRange, &previous) else { return nil }
        var stringRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString,
                                                         previousValue, &stringRef) == .success,
              let string = stringRef as? String, let character = string.first else { return nil }
        return !TypingController.isWordCharacter(character)
    }
}
