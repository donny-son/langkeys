#!/usr/bin/env swift
// Renders an emoji into Resources/AppIcon.icns.
//   swift scripts/make-icon.swift 🎏
import AppKit

let emoji = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "🎏"
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// macOS icons leave a margin; emoji fill their box, so draw at ~80% of the canvas.
func render(size: Int) -> Data {
    let canvas = CGFloat(size)
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    let font = NSFont.systemFont(ofSize: canvas * 0.8)
    let text = NSAttributedString(string: emoji, attributes: [.font: font])
    let bounds = text.size()
    text.draw(
        at: NSPoint(x: (canvas - bounds.width) / 2, y: (canvas - bounds.height) / 2))
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else { fatalError("could not render \(size)px") }
    return png
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let data = render(size: size)
    let scale1 = iconset.appendingPathComponent("icon_\(size)x\(size).png")
    if size <= 512 { try data.write(to: scale1) }
    if size >= 32 {
        let half = size / 2
        try data.write(to: iconset.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("wrote \(output.path)")
