// Draws Glance's app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

/// Draws the icon on a 1024 x 1024 canvas; smaller sizes are scaled from the same vector drawing.
func drawIcon(in ctx: CGContext) {
    let rgb = CGColorSpaceCreateDeviceRGB()
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }

    // Rounded-square base on Apple's icon grid (824 pt body inside the 1024 canvas), with a soft drop shadow.
    let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(color(0.16, 0.15, 0.50))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let background = CGGradient(colorsSpace: rgb, colors: [color(0.36, 0.45, 1.0), color(0.14, 0.11, 0.46)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let sheen = CGGradient(colorsSpace: rgb, colors: [color(1, 1, 1, 0.18), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // The eye: same almond proportions as the menu bar icon.
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: 202, y: 512))
    eye.addCurve(to: CGPoint(x: 822, y: 512), control1: CGPoint(x: 366, y: 749), control2: CGPoint(x: 658, y: 749))
    eye.addCurve(to: CGPoint(x: 202, y: 512), control1: CGPoint(x: 658, y: 275), control2: CGPoint(x: 366, y: 275))
    eye.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0.03, 0.02, 0.2, 0.45))
    ctx.addPath(eye)
    ctx.setFillColor(color(0.98, 0.98, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Iris and pupil glance to the right, clipped by the eyelids.
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()
    let center = CGPoint(x: 636, y: 512)
    let iris = CGGradient(colorsSpace: rgb, colors: [color(0.30, 0.85, 1.0), color(0.12, 0.38, 0.92)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(iris, startCenter: center, startRadius: 0, endCenter: center, endRadius: 150, options: [])
    ctx.setStrokeColor(color(0.07, 0.17, 0.55))
    ctx.setLineWidth(10)
    ctx.strokeEllipse(in: CGRect(x: center.x - 145, y: center.y - 145, width: 290, height: 290))
    ctx.setFillColor(color(0.05, 0.06, 0.16))
    ctx.fillEllipse(in: CGRect(x: center.x - 64, y: center.y - 64, width: 128, height: 128))
    ctx.setFillColor(color(1, 1, 1, 0.92))
    ctx.fillEllipse(in: CGRect(x: center.x - 78, y: center.y + 22, width: 50, height: 50))
    ctx.restoreGState()
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        drawIcon(in: ctx)
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
