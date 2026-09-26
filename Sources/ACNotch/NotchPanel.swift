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

/// How the strip is drawn on a given screen.
enum StripLayout: Equatable {
    /// No notch: a notch-shaped pill hanging from the top, `main | other | other`.
    case pill
    /// Real notch: the notch grows sideways. Main word on the left wing,
    /// the other two on the right wing, camera housing in between.
    case wings(notchWidth: CGFloat)
}

struct StripView: View {
    @ObservedObject var model: StripModel
    let layout: StripLayout

    var body: some View {
        Group {
            switch layout {
            case .pill:
                HStack(spacing: 0) {
                    ForEach(Array(model.options.enumerated()), id: \.offset) { index, option in
                        if index > 0 { separator }
                        slot(option)
                    }
                }
                .padding(.horizontal, 8)
            case .wings(let notchWidth):
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if let main = model.options.first { slot(main) }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .frame(maxWidth: .infinity)

                    Color.clear.frame(width: notchWidth)

                    HStack(spacing: 0) {
                        ForEach(Array(model.options.dropFirst().enumerated()), id: \.offset) { index, option in
                            if index > 0 { separator }
                            slot(option)
                        }
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchShape(radius: layout == .pill ? 12 : 10).fill(Color.black))
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 14)
    }

    @ViewBuilder
    private func slot(_ option: StripOption) -> some View {
        let text = Text(option.label)
            .font(.system(size: 13, weight: option.highlighted ? .semibold : .regular))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
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

/// Positions and shows the strip: wings around a real notch, or a notch-like pill on Macs without one.
final class NotchController {
    let model = StripModel()

    private let panel = NotchPanel()
    private var hideWork: DispatchWorkItem?
    private var currentLayout: StripLayout?

    private let pillHeight: CGFloat = 34
    private let pillWidth: CGFloat = 380
    private let wingWidth: CGFloat = 170

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

        let layout: StripLayout
        let frame: NSRect
        if let notch = notchRect(on: screen) {
            layout = .wings(notchWidth: notch.width)
            let width = notch.width + 2 * wingWidth
            frame = NSRect(x: notch.midX - width / 2, y: notch.minY, width: width, height: notch.height)
        } else {
            layout = .pill
            frame = NSRect(x: screen.frame.midX - pillWidth / 2, y: screen.frame.maxY - pillHeight,
                           width: pillWidth, height: pillHeight)
        }

        if layout != currentLayout {
            currentLayout = layout
            panel.contentView = FirstMouseHostingView(rootView: StripView(model: model, layout: layout))
        }
        panel.setFrame(frame, display: true)
    }

    /// The camera housing, in screen coordinates, or nil on screens without a notch.
    /// With "Preview Notch Layout" on, a fake notch is used instead.
    private func notchRect(on screen: NSScreen) -> NSRect? {
        let height = screen.safeAreaInsets.top
        if height == 0, Settings.shared.previewNotch {
            let fakeWidth: CGFloat = 180
            let fakeHeight = NSStatusBar.system.thickness
            return NSRect(x: screen.frame.midX - fakeWidth / 2, y: screen.frame.maxY - fakeHeight,
                          width: fakeWidth, height: fakeHeight)
        }
        guard height > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        guard width > 0 else { return nil }
        return NSRect(x: screen.frame.minX + left.width, y: screen.frame.maxY - height, width: width, height: height)
    }
}
