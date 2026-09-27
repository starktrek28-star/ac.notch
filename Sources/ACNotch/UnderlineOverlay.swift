import AppKit

/// A thin line drawn under a word that was just autocorrected, fading out after a moment
/// (like iOS 17). It floats above the app's window and lets every click through.
final class UnderlineOverlay {
    private let panel: NSPanel
    private var fadeWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        line.layer?.cornerRadius = 1
        panel.contentView = line
    }

    /// Underlines a word given its rectangle on screen (Cocoa coordinates).
    func show(under word: NSRect) {
        fadeWork?.cancel()
        panel.setFrame(NSRect(x: word.minX, y: word.minY - 1, width: word.width, height: 2), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func hide() {
        fadeWork?.cancel()
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        })
    }
}
