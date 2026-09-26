import CoreGraphics

/// Sends synthetic keystrokes to whatever app has focus.
/// Every event is tagged so our own event tap can ignore it.
enum Typist {
    static let marker: Int64 = 0x4143_4E54 // "ACNT"

    private static let source: CGEventSource? = {
        let src = CGEventSource(stateID: .privateState)
        src?.userData = marker
        return src
    }()

    private static let deleteKey: CGKeyCode = 51

    static func backspace(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(deleteKey, down: true)
            postKey(deleteKey, down: false)
        }
    }

    static func type(_ text: String) {
        for character in text {
            let units = Array(String(character).utf16)
            postUnicode(units, down: true)
            postUnicode(units, down: false)
        }
    }

    private static func postKey(_ key: CGKeyCode, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        send(event)
    }

    private static func postUnicode(_ units: [UniChar], down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return }
        units.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        send(event)
    }

    private static func send(_ event: CGEvent) {
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }
}
