// Renders the app icon variants: a calm meter needle on the Energy Tracker teal.
// Usage: swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

let out = CommandLine.arguments.dropFirst().first ?? "."
let size = 1024

func render(_ name: String, background: CGColor?, foreground: CGColor) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let background {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    let c = CGPoint(x: 512, y: 430)
    ctx.setStrokeColor(foreground)
    ctx.setLineCap(.round)
    // Dial arc.
    ctx.setLineWidth(64)
    ctx.addArc(center: c, radius: 300, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
    ctx.strokePath()
    // Needle, pointing calmly up-left of center.
    ctx.setLineWidth(56)
    ctx.move(to: c)
    ctx.addLine(to: CGPoint(x: c.x - 120, y: c.y + 230))
    ctx.strokePath()
    ctx.setFillColor(foreground)
    ctx.fillEllipse(in: CGRect(x: c.x - 56, y: c.y - 56, width: 112, height: 112))
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}

let teal = CGColor(srgbRed: 0x1E / 255, green: 0x7A / 255, blue: 0x61 / 255, alpha: 1)
let tealDark = CGColor(srgbRed: 0x2F / 255, green: 0xB3 / 255, blue: 0x97 / 255, alpha: 1)
render("AppIcon.png", background: teal, foreground: CGColor(gray: 1, alpha: 1))
render("AppIcon-Dark.png", background: nil, foreground: tealDark)
render("AppIcon-Tinted.png", background: nil, foreground: CGColor(gray: 1, alpha: 1))
