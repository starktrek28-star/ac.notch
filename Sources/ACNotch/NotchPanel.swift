import AppKit
import SwiftUI

final class StripModel: ObservableObject {
    @Published var options: [StripOption] = []
    @Published var layout: StripLayout = .pill
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

/// How the strip is drawn.
enum StripLayout: Equatable {
    /// Docked, no notch: a notch-shaped pill hanging from the top, `main | other | other`.
    case pill
    /// Docked on a real notch: the notch grows sideways. Main word on the left wing,
    /// the other two on the right wing, camera housing in between.
    case wings(notchWidth: CGFloat)
    /// Dragged off the notch: a capsule that stays wherever it was dropped.
    case floating
}

struct StripView: View {
    @ObservedObject var model: StripModel

    var body: some View {
        Group {
            switch model.layout {
            case .pill, .floating:
                // iPhone order: the main word sits in the middle slot.
                HStack(spacing: 0) {
                    ForEach(Array(centered.enumerated()), id: \.offset) { index, option in
                        if index > 0 { separator }
                        if let option { slot(option) } else { Color.clear.frame(maxWidth: .infinity) }
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
        .background(background)
    }

    /// Options arranged `other | main | other`. The main option is first in `model.options`;
    /// with only two, the third slot is left empty so the main word stays centred.
    private var centered: [StripOption?] {
        let options = model.options
        guard options.count >= 2 else { return options.map { $0 } }
        return [options[1], options[0], options.count > 2 ? options[2] : nil]
    }

    @ViewBuilder
    private var background: some View {
        switch model.layout {
        case .floating:
            // Frosted dark glass rather than a solid slab of black.
            ZStack {
                FrostedGlass()
                Color.black.opacity(0.3)
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        case .pill:
            NotchShape(radius: 12).fill(Color.black)
        case .wings:
            NotchShape(radius: 10).fill(Color.black)
        }
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

/// The dark blur macOS uses for its own volume and brightness pop-ups.
struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active   // stay frosted even though the panel is never the active window
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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

/// Positions and shows the strip. It lives docked on the notch (wings around a real notch,
/// a notch-like pill otherwise) until dragged off; then it floats where it was dropped.
/// Dragging uses a spring so it feels magnetic: it resists leaving the notch, pops free,
/// and gets pulled back in when dropped near it.
final class NotchController {
    let model = StripModel()
    var onPick: ((StripOption) -> Void)?
    /// Called when the strip is dragged off the notch or docked again.
    var onDockChange: (() -> Void)?

    private let panel = NotchPanel()
    private var hideWork: DispatchWorkItem?

    private let pillHeight: CGFloat = 34
    private let pillWidth: CGFloat = 380
    private let wingWidth: CGFloat = 170
    private let floatWidth: CGFloat = 330

    /// How far you pull before it breaks away from the notch.
    private let detachDistance: CGFloat = 44
    /// How close to the notch it has to be for the magnet to take it back.
    private let snapRadius: CGFloat = 110

    private struct Drag {
        var startMouse: NSPoint
        var startFrame: NSRect
        var grabOffset: CGVector
        var moved = false
        var detached: Bool
    }
    private var drag: Drag?
    /// Bumped on every show/hide so a late caret lookup can tell it's stale.
    private var showToken = 0
    /// Which side of the caret the strip sits on; kept while it still fits so it doesn't flip.
    private var belowCaret: Bool?
    private var suppressPick = false
    private var mouseMonitor: Any?

    // Spring state, tracked as centre + size so shapes morph around their middle.
    private var current = SpringRect()
    private var target = SpringRect()
    private var velocity = SpringRect()
    private var springTimer: Timer?

    init() {
        model.onPick = { [weak self] option in
            guard let self else { return }
            if self.suppressPick { self.suppressPick = false; return }
            self.onPick?(option)
        }
        panel.contentView = FirstMouseHostingView(rootView: StripView(model: model))
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in self?.handleMouse(event) ?? event
        }
    }

    var isFloating: Bool { Settings.shared.floatingCenter != nil }

    func show(_ options: [StripOption], hideAfter delay: TimeInterval? = nil) {
        hideWork?.cancel()
        showToken += 1
        guard !options.isEmpty else { hide(); return }
        model.options = options
        if let delay { hide(after: delay) }

        guard Settings.shared.followCaret else {
            place()
            reveal()
            return
        }
        // Look up the caret a moment after the keystroke, once the app has moved it,
        // so typing never waits on the lookup.
        let token = showToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, self.showToken == token else { return }
            if !self.placeAtCaret() { self.place() }
            self.reveal()
        }
    }

    private func reveal() {
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        if delay == 0 { showToken += 1 }
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// True when a screen point (Cocoa coordinates) is over the visible strip.
    func contains(_ point: NSPoint) -> Bool {
        panel.isVisible && panel.alphaValue > 0 && panel.frame.contains(point)
    }

    /// Sends a floating strip back to the notch.
    func dock() {
        Settings.shared.floatingCenter = nil
        onDockChange?()
        guard panel.isVisible, let screen = screen(containing: panel.frame.center) else { return }
        let docked = dockedPlacement(on: screen)
        setLayout(docked.layout)
        move(to: docked.frame, animated: true)
    }

    private func fadeOut() {
        guard panel.isVisible else { return }
        // Don't vanish while it's being dragged or the pointer is resting on it.
        if drag != nil || panel.frame.contains(NSEvent.mouseLocation) {
            hide(after: 1)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.stopSpring()
            self.panel.orderOut(nil)
        })
    }

    // MARK: - Placement

    /// Puts the strip a short gap above or below the text cursor, whichever side has more room,
    /// centred on it so the main word sits right over the caret.
    /// Returns false when the focused app doesn't report a cursor position.
    private func placeAtCaret() -> Bool {
        guard drag == nil, let caret = CaretLocator.caretRect(),
              let screen = screen(containing: NSPoint(x: caret.midX, y: caret.midY)) ?? NSScreen.main else { return false }
        let area = screen.visibleFrame
        let gap: CGFloat = 18
        let needed = pillHeight + gap
        let spaceBelow = caret.minY - area.minY
        let spaceAbove = area.maxY - caret.maxY

        var below = spaceBelow >= spaceAbove
        if let previous = belowCaret, (previous ? spaceBelow : spaceAbove) >= needed { below = previous }
        belowCaret = below

        let y = below ? caret.minY - gap - pillHeight / 2 : caret.maxY + gap + pillHeight / 2
        // Glide along with the caret so the main word stays right where the eyes are.
        let x = min(max(caret.midX, area.minX + floatWidth / 2 + 8), area.maxX - floatWidth / 2 - 8)

        setLayout(.floating)
        move(to: floatingFrame(center: NSPoint(x: x, y: y)), animated: panel.isVisible && panel.alphaValue > 0)
        return true
    }

    private func place() {
        // Mid-drag or mid-animation, the spring owns the frame.
        guard drag == nil, springTimer == nil else { return }
        if let center = Settings.shared.floatingCenter, screen(containing: center) != nil {
            setLayout(.floating)
            move(to: floatingFrame(center: clamped(center)), animated: false)
        } else {
            Settings.shared.floatingCenter = nil
            let mouse = NSEvent.mouseLocation
            guard let screen = screen(containing: mouse) ?? NSScreen.main else { return }
            let docked = dockedPlacement(on: screen)
            setLayout(docked.layout)
            move(to: docked.frame, animated: false)
        }
    }

    private func setLayout(_ layout: StripLayout) {
        if model.layout != layout { model.layout = layout }
    }

    private func dockedPlacement(on screen: NSScreen) -> (layout: StripLayout, frame: NSRect) {
        if let notch = notchRect(on: screen) {
            let width = notch.width + 2 * wingWidth
            return (.wings(notchWidth: notch.width),
                    NSRect(x: notch.midX - width / 2, y: notch.minY, width: width, height: notch.height))
        }
        return (.pill, NSRect(x: screen.frame.midX - pillWidth / 2, y: screen.frame.maxY - pillHeight,
                              width: pillWidth, height: pillHeight))
    }

    private func floatingFrame(center: NSPoint) -> NSRect {
        NSRect(x: center.x - floatWidth / 2, y: center.y - pillHeight / 2, width: floatWidth, height: pillHeight)
    }

    /// Keeps a floating strip fully on screen.
    private func clamped(_ center: NSPoint) -> NSPoint {
        guard let screen = screen(containing: center) ?? NSScreen.main else { return center }
        let area = screen.frame.insetBy(dx: floatWidth / 2 + 8, dy: pillHeight / 2 + 8)
        return NSPoint(x: min(max(center.x, area.minX), area.maxX),
                       y: min(max(center.y, area.minY), area.maxY))
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
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

    // MARK: - Dragging

    private func handleMouse(_ event: NSEvent) -> NSEvent? {
        // Following the caret, the strip places itself: clicks work, dragging doesn't.
        guard event.window === panel, !Settings.shared.followCaret else {
            if event.type == .leftMouseDown { suppressPick = false }
            return event
        }
        let mouse = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            suppressPick = false
            hideWork?.cancel()
            let frame = panel.frame
            drag = Drag(startMouse: mouse,
                        startFrame: frame,
                        grabOffset: isFloating ? CGVector(dx: frame.midX - mouse.x, dy: frame.midY - mouse.y) : .zero,
                        detached: isFloating)
            return event

        case .leftMouseDragged:
            guard var d = drag else { return event }
            let dx = mouse.x - d.startMouse.x, dy = mouse.y - d.startMouse.y
            let distance = hypot(dx, dy)
            if !d.moved && distance < 4 { return event }
            d.moved = true

            if !d.detached {
                if distance < detachDistance {
                    // Held by the magnet: it only gives a little.
                    move(to: d.startFrame.offsetBy(dx: dx * 0.25, dy: dy * 0.25), animated: true)
                } else {
                    // Breaks free and springs into a floating capsule under the pointer.
                    d.detached = true
                    d.grabOffset = .zero
                    setLayout(.floating)
                    move(to: floatingFrame(center: mouse), animated: true)
                }
            } else {
                var center = NSPoint(x: mouse.x + d.grabOffset.dx, y: mouse.y + d.grabOffset.dy)
                if let dockCenter = dockCenter(near: center) {
                    // Near the notch the magnet starts pulling it home.
                    let gap = hypot(center.x - dockCenter.x, center.y - dockCenter.y)
                    if gap < snapRadius {
                        let pull = (1 - gap / snapRadius) * 0.5
                        center.x += (dockCenter.x - center.x) * pull
                        center.y += (dockCenter.y - center.y) * pull
                    }
                }
                move(to: floatingFrame(center: center), animated: true)
            }
            drag = d
            return nil

        case .leftMouseUp:
            guard let d = drag else { return event }
            drag = nil
            guard d.moved else { return event }
            suppressPick = true   // a drag is not a click on a suggestion

            if !d.detached {
                move(to: d.startFrame, animated: true)   // didn't pull hard enough: snap back
            } else {
                let center = target.rect.center
                if let dockCenter = dockCenter(near: center),
                   hypot(center.x - dockCenter.x, center.y - dockCenter.y) < snapRadius {
                    dock()
                } else {
                    let resting = clamped(center)
                    Settings.shared.floatingCenter = resting
                    onDockChange?()
                    move(to: floatingFrame(center: resting), animated: true)
                }
            }
            hide(after: 2.5)
            return event

        default:
            return event
        }
    }

    private func dockCenter(near point: NSPoint) -> NSPoint? {
        guard let screen = screen(containing: point) ?? NSScreen.main else { return nil }
        return dockedPlacement(on: screen).frame.center
    }

    // MARK: - Spring animation

    private func move(to rect: NSRect, animated: Bool) {
        target = SpringRect(rect)
        guard animated, panel.isVisible else {
            stopSpring()
            current = target
            velocity = SpringRect()
            panel.setFrame(rect, display: true)
            return
        }
        if springTimer == nil {
            current = SpringRect(panel.frame)
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.stepSpring() }
            RunLoop.main.add(timer, forMode: .common)
            springTimer = timer
        }
    }

    private func stepSpring() {
        // Slightly under-damped: a soft overshoot that reads as magnetic, not bouncy.
        let dt: CGFloat = 1.0 / 120.0, stiffness: CGFloat = 520, damping: CGFloat = 34
        var settled = true
        for key in SpringRect.keys {
            let offset = target[key] - current[key]
            let accel = stiffness * offset - damping * velocity[key]
            velocity[key] += accel * dt
            current[key] += velocity[key] * dt
            if abs(offset) > 0.3 || abs(velocity[key]) > 2 { settled = false }
        }
        if settled {
            current = target
            velocity = SpringRect()
            stopSpring()
        }
        panel.setFrame(current.rect, display: true)
    }

    private func stopSpring() {
        springTimer?.invalidate()
        springTimer = nil
    }
}

/// A rectangle as centre + size, so it can be animated one number at a time.
private struct SpringRect {
    enum Key: CaseIterable { case x, y, width, height }
    static let keys = Key.allCases

    var x: CGFloat = 0, y: CGFloat = 0, width: CGFloat = 0, height: CGFloat = 0

    init() {}
    init(_ rect: NSRect) {
        x = rect.midX; y = rect.midY; width = rect.width; height = rect.height
    }

    var rect: NSRect { NSRect(x: x - width / 2, y: y - height / 2, width: width, height: height) }

    subscript(key: Key) -> CGFloat {
        get {
            switch key {
            case .x: return x
            case .y: return y
            case .width: return width
            case .height: return height
            }
        }
        set {
            switch key {
            case .x: x = newValue
            case .y: y = newValue
            case .width: width = newValue
            case .height: height = newValue
            }
        }
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
