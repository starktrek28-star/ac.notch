import ApplicationServices

/// Uses the Accessibility API to peek at the character before the text cursor.
enum AXProbe {
    /// true: cursor is at the start of a word. false: it's in the middle of one.
    /// nil: the app doesn't say.
    static func cursorIsAtWordStart() -> Bool? {
        guard let focused = CaretLocator.focusedElement() else { return nil }

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
