import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Development helper: render the popover to a PNG and exit.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-ui"),
   CommandLine.arguments.count > flagIndex + 1 {
    let path = CommandLine.arguments[flagIndex + 1]
    Task { @MainActor in
        let succeeded = UISnapshot.render(to: path, model: AppModel())
        exit(succeeded ? 0 : 1)
    }
    app.run()
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
