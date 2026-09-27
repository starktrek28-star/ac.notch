import AppKit

/// Watches every keystroke (via a CGEvent tap), tracks the word being typed,
/// updates the notch strip and swaps in corrections when a word ends.
final class TypingController {
    /// Whether we know the buffer holds the whole word (and not the tail of one).
    private enum Trust { case trusted, unknown, untrusted }

    let notch: NotchController
    var onToggleHotkey: (() -> Void)?
    var onHomeHotkey: (() -> Void)?

    /// How long the strip stays after typing stops: about four blinks of the text cursor.
    private let idleFade: TimeInterval = 4
    private let suggester = Suggester()
    private let underline = UnderlineOverlay()
    private var tap: CFMachPort?
    private var buffer = ""
    /// What the strip is showing for the word being typed.
    private var currentOptions: [StripOption] = []
    /// After backspacing into a word that was autocorrected: the original is on offer (Tab takes it).
    private var revertOffer: (original: String, corrected: String)?
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

    /// Forget the word in progress. A hard reset (click elsewhere, a shortcut, switching off)
    /// hides the strip at once; a soft one (Return, arrows, other punctuation) leaves it up,
    /// showing what was just typed, until typing pauses.
    func reset(soft: Bool = false) {
        let word = buffer
        let trusted = trust == .trusted
        currentOptions = []
        revertOffer = nil
        buffer = ""
        trust = .unknown
        lastCorrection = nil
        guard soft else {
            notch.hide()
            notch.clearTrail()
            return
        }
        if trusted, !word.isEmpty {
            notch.commitWord(word)
            notch.show([], hideAfter: idleFade)
        } else {
            notch.hide(after: idleFade)
        }
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
            if !notch.contains(NSEvent.mouseLocation) { reset(soft: true) }
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
            reset(soft: true)
            return true
        }

        // Tab while the original word is on offer puts it back.
        if keyCode == 48, let offer = revertOffer, !flags.contains(.maskShift), !flags.contains(.maskAlternate) {
            revert(offer)
            return false
        }

        if keyCode == 51 { return handleBackspace() }
        lastCorrection = nil
        revertOffer = nil

        switch keyCode {
        case 53:   // Escape
            reset()
            return true
        // Return, Enter, Tab, Home, PageUp, ForwardDelete, End, PageDown, arrows
        case 36, 76, 48, 115, 116, 117, 119, 121, 123, 124, 125, 126:
            reset(soft: true)
            return true
        default:
            break
        }

        guard let text = event.typedText, text.count == 1, let character = text.first else {
            reset(soft: true)
            return true
        }

        if TypingController.isWordCharacter(character) {
            if buffer.isEmpty, trust == .unknown {
                trust = (AXProbe.cursorIsAtWordStart() ?? true) ? .trusted : .untrusted
            }
            buffer.append(character)
            if trust == .trusted { refreshStrip() } else { notch.hide(after: idleFade) }
            return true
        }

        if TypingController.isBoundary(character) {
            return finishWord(boundary: text)
        }

        reset(soft: true)   // other punctuation: the word ends, the strip stays
        return true
    }

    private func handleBackspace() -> Bool {
        // Backspace right after an autocorrect deletes the space as usual, and a second pill
        // pops out offering the word you actually typed (like iPhone). Tab or a click takes it.
        if let correction = lastCorrection {
            lastCorrection = nil
            revertOffer = (correction.original, correction.corrected)
            buffer = correction.corrected
            trust = .trusted
            notch.uncommitWord()
            currentOptions = [
                StripOption(text: correction.corrected, kind: .info, highlighted: true),
                StripOption(text: correction.original, kind: .original, quoted: true, acceptsTab: true),
            ]
            notch.show(currentOptions, hideAfter: idleFade)
            return true
        }
        revertOffer = nil
        if buffer.isEmpty {
            // We've backed into the previous word, whose start we can't be sure of.
            trust = .unknown
            notch.uncommitWord()
            notch.show([], hideAfter: idleFade)
        } else {
            buffer.removeLast()
            if buffer.isEmpty || trust != .trusted { notch.hide(after: idleFade) } else { refreshStrip() }
        }
        return true
    }

    private func finishWord(boundary: String) -> Bool {
        Diagnostics.log("word end (\(buffer.count) letters, trusted=\(trust == .trusted))")
        let word = buffer
        let wasTrusted = trust == .trusted
        buffer = ""
        currentOptions = []
        trust = .trusted

        guard wasTrusted, !word.isEmpty, Settings.shared.autocorrect,
              let corrected = suggester.analyze(word).autocorrection, corrected != word,
              !CaretLocator.focusIsAddressBar() else {
            // The finished word joins the trail; the strip fades once typing pauses.
            if wasTrusted, !word.isEmpty {
                notch.commitWord(word)
                notch.show([], hideAfter: idleFade)
            } else {
                notch.hide(after: idleFade)
            }
            return true
        }

        Typist.backspace(word.count)
        Typist.type(corrected + boundary)
        lastCorrection = (word, corrected, boundary)
        notch.commitWord(corrected)
        notch.show([], hideAfter: idleFade)

        // Briefly underline the corrected word once the app has drawn it.
        let length = corrected.utf16.count, offset = length + boundary.utf16.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.lastCorrection?.corrected == corrected,
                  let rect = CaretLocator.textRectBeforeCaret(offset: offset, length: length) else { return }
            self.underline.show(under: rect)
        }
        return false
    }

    private func refreshStrip() {
        guard !buffer.isEmpty else { notch.hide(after: idleFade); return }
        currentOptions = suggester.analyze(buffer).options
        notch.show(currentOptions)
    }

    // MARK: - Actions

    /// Swaps an autocorrected word (caret right after it) back to what was typed.
    private func revert(_ offer: (original: String, corrected: String)) {
        revertOffer = nil
        underline.hide()
        Typist.backspace(offer.corrected.count)
        Typist.type(offer.original)
        suggester.rejected(offer.original)
        buffer = offer.original
        trust = .trusted
        currentOptions = [StripOption(text: offer.original, kind: .typed, highlighted: true)]
        notch.show(currentOptions, hideAfter: idleFade)
    }

    /// A suggestion was clicked in the strip.
    private func pick(_ option: StripOption) {
        switch option.kind {
        case .info:
            return
        case .original:
            guard let offer = revertOffer else { return }
            revert(offer)
        case .typed:
            guard !buffer.isEmpty, trust == .trusted else { return }
            suggester.ignore(buffer)
            Typist.type(" ")
            notch.commitWord(buffer)
            buffer = ""
            notch.show([], hideAfter: idleFade)
        case .correction, .suggestion:
            guard !buffer.isEmpty, trust == .trusted else { return }
            Typist.backspace(buffer.count)
            Typist.type(option.text + " ")
            notch.commitWord(option.text)
            buffer = ""
            notch.show([], hideAfter: idleFade)
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
