// Generates the NightOwl app icon (a 🦉 on a night-sky rounded rect).
// Run via build.sh when Resources/AppIcon.icns is missing:
//   swift scripts/make-icon.swift /tmp/nightowl-icon-1024.png
import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "/tmp/nightowl-icon-1024.png"

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Night-sky background with macOS-style rounded corners
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let rounded = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.30, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.12, alpha: 1),
])!
gradient.draw(in: rounded, angle: -90)

// A few stars
NSColor(calibratedWhite: 1, alpha: 0.9).setFill()
for (x, y, r) in [(180.0, 800.0, 9.0), (840.0, 850.0, 7.0), (720.0, 700.0, 5.0),
                  (250.0, 640.0, 5.0), (880.0, 560.0, 6.0), (140.0, 480.0, 6.0)] {
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r * 2, height: r * 2)).fill()
}

// The owl
let owl = "🦉" as NSString
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 620)]
let owlSize = owl.size(withAttributes: attrs)
owl.draw(at: NSPoint(x: (size - owlSize.width) / 2,
                     y: (size - owlSize.height) / 2 - 30),
         withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("icon render failed\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
