import AppKit
import SwiftUI

final class StripModel: ObservableObject {
    @Published var options: [StripOption] = []
    var onPick: ((StripOption) -> Void)?
}

/// Black shape hanging from the top of the screen: square top, rounded bottom.
struct NotchShape: Shape {
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct StripView: View {
    @ObservedObject var model: StripModel
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            HStack(spacing: 0) {
                ForEach(Array(model.options.enumerated()), id: \.offset) { index, option in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 1, height: 16)
                    }
                    slot(option)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchShape().fill(Color.black))
    }

    @ViewBuilder
    private func slot(_ option: StripOption) -> some View {
        let text = Text(option.label)
            .font(.system(size: 13, weight: option.highlighted ? .semibold : .regular))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(option.highlighted ? Color.white.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())

        if option.kind == .info {
            text
        } else {
            Button { model.onPick?(option) } label: { text }
                .buttonStyle(.plain)
        }
    }
}

/// A panel that never takes keyboard focus, so the app you're typing in keeps it.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a suggestion register even though the panel isn't key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Positions and shows the strip on the notch (or a notch-like pill on Macs without one).
final class NotchController {
    let model = StripModel()

    private let panel = NotchPanel()
    private var hideWork: DispatchWorkItem?
    private var currentInset: CGFloat = -1

    private let stripHeight: CGFloat = 34
    private let width: CGFloat = 380

    func show(_ options: [StripOption], hideAfter delay: TimeInterval? = nil) {
        hideWork?.cancel()
        guard !options.isEmpty else { hide(); return }
        model.options = options
        layout()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        if let delay { hide(after: delay) }
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// True when a screen point (Cocoa coordinates) is over the visible strip.
    func contains(_ point: NSPoint) -> Bool {
        panel.isVisible && panel.alphaValue > 0 && panel.frame.contains(point)
    }

    private func fadeOut() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        })
    }

    private func layout() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }

        // Real notch: sit below the camera housing. No notch: a pill that looks like one.
        let inset = screen.safeAreaInsets.top
        let frame = NSRect(x: screen.frame.midX - width / 2,
                           y: screen.frame.maxY - inset - stripHeight,
                           width: width,
                           height: inset + stripHeight)

        if inset != currentInset {
            currentInset = inset
            let view = FirstMouseHostingView(rootView: StripView(model: model, topInset: inset))
            panel.contentView = view
        }
        panel.setFrame(frame, display: true)
    }
}
