import AppKit

/// Watches every keystroke (via a CGEvent tap), tracks the word being typed,
/// updates the notch strip and swaps in corrections when a word ends.
final class TypingController {
    /// Whether we know the buffer holds the whole word (and not the tail of one).
    private enum Trust { case trusted, unknown, untrusted }

    let notch: NotchController
    var onToggleHotkey: (() -> Void)?
    var onHomeHotkey: (() -> Void)?

    private let suggester = Suggester()
    private var tap: CFMachPort?
    private var buffer = ""
    private var trust: Trust = .unknown
    private var lastCorrection: (original: String, corrected: String, boundary: String)?

    init(notch: NotchController) {
        self.notch = notch
        notch.onPick = { [weak self] option in self?.pick(option) }
    }

    var isRunning: Bool { tap != nil }

    /// Needs Accessibility permission; returns false without it.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: eventTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    func reset() {
        buffer = ""
        trust = .unknown
        lastCorrection = nil
        notch.hide()
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // Clicking a suggestion must not throw away the word we're about to replace.
            if !notch.contains(NSEvent.mouseLocation) { reset() }
            return pass
        case .keyDown:
            return handleKey(event) ? pass : nil
        default:
            return pass
        }
    }

    /// Returns false to swallow the keystroke.
    private func handleKey(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Typist.marker { return true }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Control + Option + Space toggles everything on/off.
        if keyCode == 49, flags.contains(.maskControl), flags.contains(.maskAlternate), !flags.contains(.maskCommand) {
            DispatchQueue.main.async { [weak self] in self?.onToggleHotkey?() }
            return false
        }

        // Control + Option + H calls the strip back to the text cursor.
        if keyCode == 4, flags.contains(.maskControl), flags.contains(.maskAlternate), !flags.contains(.maskCommand) {
            DispatchQueue.main.async { [weak self] in self?.onHomeHotkey?() }
            return false
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard Settings.shared.enabled, !Settings.shared.isExcluded(frontmost) else {
            if !buffer.isEmpty || lastCorrection != nil { reset() }
            return true
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            reset()
            return true
        }

        if keyCode == 51 { return handleBackspace() }
        lastCorrection = nil

        switch keyCode {
        // Return, Enter, Tab, Escape, Home, PageUp, ForwardDelete, End, PageDown, arrows
        case 36, 76, 48, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126:
            reset()
            return true
        default:
            break
        }

        guard let text = event.typedText, text.count == 1, let character = text.first else {
            reset()
            return true
        }

        if TypingController.isWordCharacter(character) {
            if buffer.isEmpty, trust == .unknown {
                trust = (AXProbe.cursorIsAtWordStart() ?? true) ? .trusted : .untrusted
            }
            buffer.append(character)
            if trust == .trusted { refreshStrip() } else { notch.hide() }
            return true
        }

        if TypingController.isBoundary(character) {
            return finishWord(boundary: text)
        }

        reset()
        return true
    }

    private func handleBackspace() -> Bool {
        // Backspace right after an autocorrect puts back what you typed (like iPhone).
        if let correction = lastCorrection {
            lastCorrection = nil
            revert(correction, keepBoundary: false)
            return false
        }
        if buffer.isEmpty {
            // We've backed into text we never saw.
            trust = .unknown
            notch.hide()
        } else {
            buffer.removeLast()
            if buffer.isEmpty || trust != .trusted { notch.hide() } else { refreshStrip() }
        }
        return true
    }

    private func finishWord(boundary: String) -> Bool {
        let word = buffer
        let wasTrusted = trust == .trusted
        buffer = ""
        trust = .trusted

        guard wasTrusted, !word.isEmpty, Settings.shared.autocorrect,
              let corrected = suggester.analyze(word).autocorrection, corrected != word,
              !CaretLocator.focusIsAddressBar() else {
            notch.hide(after: 3)   // stay up between words; only fade once typing pauses
            return true
        }

        Typist.backspace(word.count)
        Typist.type(corrected + boundary)
        lastCorrection = (word, corrected, boundary)
        notch.show([
            StripOption(text: corrected, kind: .info, highlighted: true),
            StripOption(text: word, kind: .original, quoted: true),
        ], hideAfter: 3)
        return false
    }

    private func refreshStrip() {
        guard !buffer.isEmpty else { notch.hide(); return }
        notch.show(suggester.analyze(buffer).options)
    }

    // MARK: - Actions

    private func revert(_ correction: (original: String, corrected: String, boundary: String), keepBoundary: Bool) {
        Typist.backspace(correction.corrected.count + correction.boundary.count)
        Typist.type(correction.original + (keepBoundary ? correction.boundary : ""))
        suggester.ignore(correction.original)
        trust = .trusted
        if keepBoundary {
            buffer = ""
            notch.hide(after: 0.4)
        } else {
            buffer = correction.original
            refreshStrip()
        }
    }

    /// A suggestion was clicked in the strip.
    private func pick(_ option: StripOption) {
        switch option.kind {
        case .info:
            return
        case .original:
            guard let correction = lastCorrection else { return }
            lastCorrection = nil
            revert(correction, keepBoundary: true)
        case .typed:
            guard !buffer.isEmpty, trust == .trusted else { return }
            suggester.ignore(buffer)
            Typist.type(" ")
            buffer = ""
            notch.hide()
        case .correction, .suggestion:
            guard !buffer.isEmpty, trust == .trusted else { return }
            Typist.backspace(buffer.count)
            Typist.type(option.text + " ")
            buffer = ""
            notch.hide()
        }
    }

    // MARK: - Character classes

    static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "\u{2019}"
    }

    static func isBoundary(_ c: Character) -> Bool {
        c == " " || ".,!?;:\")".contains(c)
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<TypingController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

private extension CGEvent {
    /// The text this keystroke would type, if any.
    var typedText: String? {
        var length = 0
        var units = [UniChar](repeating: 0, count: 8)
        keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        return length > 0 ? String(utf16CodeUnits: units, count: length) : nil
    }
}
