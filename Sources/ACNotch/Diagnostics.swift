import AppKit

/// A short, local record of what AC Notch saw (where it found the cursor, why it showed or
/// hid the strip), so problems can be diagnosed from real use. Never records typed text,
/// stays in memory, and is only shared if the user copies it from the menu.
enum Diagnostics {
    private static var lines: [String] = []
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: @autoclosure () -> String) {
        lines.append("\(formatter.string(from: Date())) \(message())")
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
    }

    static func copyToClipboard() {
        let header = "AC Notch diagnostics · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(([header] + lines).joined(separator: "\n"), forType: .string)
    }

    static func frontApp() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    }

    static func describe(_ r: NSRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height)))"
    }
}
