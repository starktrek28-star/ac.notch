import AppKit
import SwiftUI

final class StripModel: ObservableObject {
    /// The pills for the word being typed (the word, plus the original on offer after a backspace).
    @Published var options: [StripOption] = []
    /// The word typed last, shown between words so the strip never blanks out.
    @Published var trail: [TrailWord] = []
    /// Identifies the word being typed, so its pill glides into the trail instead of popping.
    @Published var currentID = 0
    @Published var layout: StripLayout = .pill
    var onPick: ((StripOption) -> Void)?
}

struct TrailWord: Equatable {
    let id: Int
    let text: String
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
            case .floating:
                // One pill: the word you're typing (greyed when it will be fixed). After a
                // backspace, the original word pops out beside it in its own pill.
                HStack(spacing: 6) {
                    ForEach(Array(model.options.enumerated()), id: \.offset) { _, option in
                        pill(option)
                            .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .pill:
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

    /// Options in reading order: what you typed on the left, the other option on the right,
    /// so it reads like `“teh” | the` or `hel | hello`.
    private var centered: [StripOption?] {
        let options = model.options
        let typed = options.filter { $0.kind == .typed || $0.kind == .original }
        return (typed + options.filter { $0.kind != .typed && $0.kind != .original }).map { $0 }
    }

    @ViewBuilder
    private var background: some View {
        switch model.layout {
        case .floating:
            Color.clear   // each floating pill draws its own glass
        case .pill:
            NotchShape(radius: 12).fill(Color.black)
        case .wings:
            NotchShape(radius: 10).fill(Color.black)
        }
    }

    private func pill(_ option: StripOption) -> some View {
        slot(option)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(height: 30)
            .background(glassCapsule)
    }

    /// Frosted dark glass rather than a solid slab of black.
    private var glassCapsule: some View {
        ZStack {
            FrostedGlass()
            Color.black.opacity(0.3)
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 14)
    }

    @ViewBuilder
    private func slot(_ option: StripOption) -> some View {
        let text = (Text(option.label)
                    + Text(option.acceptsTab ? " \u{21E5}" : "")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.5)))
            .font(.system(size: 13, weight: option.highlighted ? .semibold : .regular))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(option.highlighted ? Color.white.opacity(0.28) : Color.clear)
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
    /// The docked pill (Macs without a notch) keeps a notch-like minimum width.
    private var pillWidth: CGFloat { max(floatWidth, 200) }
    private let wingWidth: CGFloat = 170
    private func pillWidth(_ text: String, bold: Bool = false) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: bold ? .semibold : .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 16 + 8 + 6
    }

    private var optionWidths: [CGFloat] {
        model.options.map { pillWidth($0.displayText, bold: $0.highlighted) }
    }

    /// The pills side by side, 6 pt apart.
    private var floatWidth: CGFloat {
        let widths = optionWidths
        return max(widths.reduce(0, +) + 6 * CGFloat(max(widths.count - 1, 0)) + 2, 40)
    }

    /// Distance from the strip's left edge to the point that should sit over the caret:
    /// the middle of the main pill.
    private var caretAnchor: CGFloat { (optionWidths.first ?? floatWidth) / 2 }

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
    /// Where the strip was dragged to while following the cursor; nil when it's home.
    private var parkedCenter: NSPoint?
    /// When the caret itself (not just its text field) was last found.
    private var lastPreciseCaret = Date.distantPast
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

    /// True when the strip was dragged away from the cursor (its home) and left there.
    var isParked: Bool { parkedCenter != nil }

    /// Sends the strip back to hovering by the text cursor.
    func returnHome() {
        parkedCenter = nil
        onDockChange?()
        if panel.isVisible, panel.alphaValue > 0, !(model.options.isEmpty && model.trail.isEmpty) {
            if !placeAtCaret() { place() }
            hide(after: 2.5)
        } else {
            show([StripOption(text: "Back to cursor", kind: .info)], hideAfter: 1.2)
        }
    }

    /// The word being typed is done; remember it so the strip can keep showing it until the
    /// next word starts, instead of blanking out on every space.
    func commitWord(_ text: String) {
        model.trail = [TrailWord(id: model.currentID, text: text)]
        model.currentID += 1
    }

    /// Backspacing into the last word: forget it again.
    func uncommitWord() {
        guard let last = model.trail.last else { return }
        model.trail.removeLast()
        model.currentID = last.id
    }

    func clearTrail() {
        model.trail = []
        model.currentID += 1
    }

    func show(_ options: [StripOption], hideAfter delay: TimeInterval? = nil) {
        hideWork?.cancel()
        showToken += 1
        // Between words, keep showing the word just typed.
        let shown = options.isEmpty ? model.trail.suffix(1).map { StripOption(text: $0.text, kind: .info) } : options
        guard !shown.isEmpty else {
            Diagnostics.log("hide: nothing to show")
            hide()
            return
        }
        if let delay { hide(after: delay) }

        guard Settings.shared.followCaret else {
            apply(shown)
            place()
            reveal()
            return
        }
        // Parked somewhere by hand: stay there until called home.
        if let parked = parkedCenter {
            apply(shown)
            if drag == nil, springTimer == nil {
                setLayout(.floating)
                move(to: floatingFrame(center: clamped(parked)), animated: false)
            }
            reveal()
            return
        }
        // Look up the caret a moment after the keystroke, once the app has moved it, so typing
        // never waits on the lookup. The words and the position then change together, in one go.
        let token = showToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, self.showToken == token else { return }
            self.apply(shown)
            // In a browser's address bar the strip sits on the notch instead of following.
            if CaretLocator.focusIsAddressBar() {
                Diagnostics.log("place: address bar, on the notch")
                self.stopSpring()
                self.place()
            } else if !self.placeAtCaret() {
                Diagnostics.log("place: no caret, on the notch")
                self.stopSpring()
                self.place()
            }
            self.reveal()
        }
    }

    /// Words change instantly, like typing itself; only the original-word pill popping out is animated.
    private func apply(_ options: [StripOption]) {
        guard options != model.options else { return }
        if options.count > 1 && model.options.count <= 1 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { model.options = options }
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { model.options = options }
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
        if delay == 0, panel.isVisible { Diagnostics.log("hide: now") }
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
        Diagnostics.log("fade out")
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
            self.clearTrail()
        })
    }

    // MARK: - Placement

    /// Puts the strip a short gap above or below the text cursor, whichever side has more room,
    /// centred on it so the main word sits right over the caret.
    /// Returns false when the focused app doesn't report a cursor position.
    private func placeAtCaret() -> Bool {
        guard drag == nil else { return false }
        let showing = panel.isVisible && panel.alphaValue > 0 && model.layout == .floating
        // A lookup can miss for a moment (a web page mid-update, a space with no width yet).
        // If the strip is already out, leave it where it is rather than hiding or jumping.
        guard let found = CaretLocator.caret() else {
            if showing { Diagnostics.log("place: caret lookup missed, staying put") }
            return showing
        }
        if !found.precise, showing, Date().timeIntervalSince(lastPreciseCaret) < 5 {
            Diagnostics.log("place: only a rough position, staying put")
            return true
        }
        if found.precise { lastPreciseCaret = Date() }
        let caret = found.rect
        guard let screen = screen(containing: NSPoint(x: caret.midX, y: caret.midY)) ?? NSScreen.main else { return false }
        let area = screen.visibleFrame
        let gap: CGFloat = 18
        let needed = pillHeight + gap
        let spaceBelow = caret.minY - area.minY
        let spaceAbove = area.maxY - caret.maxY

        var below = spaceBelow >= spaceAbove
        if let previous = belowCaret, (previous ? spaceBelow : spaceAbove) >= needed { below = previous }
        belowCaret = below

        let y = below ? caret.minY - gap - pillHeight / 2 : caret.maxY + gap + pillHeight / 2
        // Glide along with the caret: the main pill sits right over it.
        let width = floatWidth
        let left = min(max(caret.midX - caretAnchor, area.minX + 8), area.maxX - width - 8)

        setLayout(.floating)
        move(to: NSRect(x: left, y: y - pillHeight / 2, width: width, height: pillHeight),
             animated: panel.isVisible && panel.alphaValue > 0)
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
        guard event.window === panel else { return event }
        let mouse = NSEvent.mouseLocation
        // Following the cursor, the strip is already a free capsule: dragging just parks it.
        let following = Settings.shared.followCaret
        let alreadyFree = following || isFloating

        switch event.type {
        case .leftMouseDown:
            suppressPick = false
            hideWork?.cancel()
            let frame = panel.frame
            drag = Drag(startMouse: mouse,
                        startFrame: frame,
                        grabOffset: alreadyFree ? CGVector(dx: frame.midX - mouse.x, dy: frame.midY - mouse.y) : .zero,
                        detached: alreadyFree)
            return event

        case .leftMouseDragged:
            guard var d = drag else { return event }
            let dx = mouse.x - d.startMouse.x, dy = mouse.y - d.startMouse.y
            let distance = hypot(dx, dy)
            if !d.moved && distance < (following ? 16 : 4) { return event }
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
                if !following, let dockCenter = dockCenter(near: center) {
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

            if following {
                let resting = clamped(target.rect.center)
                parkedCenter = resting
                onDockChange?()
                move(to: floatingFrame(center: resting), animated: true)
            } else if !d.detached {
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
        // Only the position glides. The size snaps at once, keeping the left edge put, so the
        // pill's glass never lags behind (and clips) the words inside it.
        let leftEdge = current.x - current.width / 2, bottomEdge = current.y - current.height / 2
        current.width = target.width
        current.height = target.height
        current.x = leftEdge + current.width / 2
        current.y = bottomEdge + current.height / 2
        velocity.width = 0
        velocity.height = 0
        panel.setFrame(current.rect, display: true)
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
