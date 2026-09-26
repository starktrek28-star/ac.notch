import AppKit

let app = NSApplication.shared
let controller = AppController()
app.setActivationPolicy(.accessory)
controller.start()
app.run()
