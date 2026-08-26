import AppKit
import SwiftUI

/// Renders the popover to a PNG without showing it.
///
/// A menu bar popover cannot be captured by screenshot tooling, so this is how
/// the layout gets checked during development. Invoked with
/// `Lithium --render-ui <path>`, which renders and exits.
enum UISnapshot {
    @MainActor
    static func render(to path: String, model: AppModel) -> Bool {
        // ImageRenderer draws the SwiftUI tree directly. Capturing an NSHostingView
        // with cacheDisplay instead loses all the text, which is layer-backed.
        let renderer = ImageRenderer(
            content: PopoverContentView(model: model).frame(width: 380)
        )
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("could not render the popover\n".utf8))
            return false
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            let size = image.size
            FileHandle.standardOutput.write(
                Data("wrote \(Int(size.width))x\(Int(size.height)) to \(path)\n".utf8)
            )
            return true
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            return false
        }
    }
}
