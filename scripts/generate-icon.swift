#!/usr/bin/env swift
// Generate Vela's app icon PNGs into Vela/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/generate-icon.swift [output-dir]
//
// Motif: a folder under a night sky, with the Vela ("sail") constellation above it.
// Drawn in a 1024pt coordinate space (origin top-left) and scaled for each size.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Vela/Assets.xcassets/AppIcon.appiconset"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radialGlow(_ ctx: CGContext, center: CGPoint, radius: CGFloat, _ inner: CGColor, _ outer: CGColor) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [inner, outer] as CFArray, locations: nil)!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

// Four-pointed sparkle star
func sparklePath(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let inner = r * 0.22
    path.move(to: CGPoint(x: c.x, y: c.y - r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
    path.closeSubpath()
    return path
}

func drawIcon(_ ctx: CGContext) {
    // macOS icon grid: 824pt body centered in a 1024pt canvas
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x101A3A))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Night sky
    linearGradient(ctx, [color(0x0A1430), color(0x1B2A6B), color(0x3A3F9E)],
                   from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    radialGlow(ctx, center: CGPoint(x: 512, y: 330), radius: 420, color(0x7FA2FF, 0.28), color(0x7FA2FF, 0))

    // Background stars
    let dust: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (190, 220, 5, 0.7), (260, 470, 3.5, 0.5), (300, 160, 3, 0.45), (420, 140, 4, 0.6),
        (800, 190, 4.5, 0.65), (850, 420, 3, 0.5), (760, 520, 3.5, 0.4), (170, 380, 3, 0.4),
        (640, 120, 3, 0.5), (880, 300, 3, 0.45), (220, 560, 2.5, 0.35), (580, 480, 2.5, 0.3),
    ]
    for (x, y, r, a) in dust {
        ctx.setFillColor(color(0xFFFFFF, a))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Vela constellation, arranged like a sail
    let stars: [CGPoint] = [
        CGPoint(x: 380, y: 465), // tack
        CGPoint(x: 445, y: 320), // luff
        CGPoint(x: 500, y: 180), // head (bright)
        CGPoint(x: 650, y: 315), // leech
        CGPoint(x: 720, y: 465), // clew
    ]
    let lines: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]
    ctx.setStrokeColor(color(0xCFE0FF, 0.55))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    for (a, b) in lines {
        ctx.move(to: stars[a])
        ctx.addLine(to: stars[b])
    }
    ctx.strokePath()

    for (i, p) in stars.enumerated() {
        let r: CGFloat = i == 2 ? 15 : 10
        radialGlow(ctx, center: p, radius: r * 3.2, color(0xBFD4FF, 0.55), color(0xBFD4FF, 0))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
    // Sparkle on the brightest star
    ctx.addPath(sparklePath(center: stars[2], radius: 62))
    ctx.setFillColor(color(0xFFFFFF, 0.95))
    ctx.fillPath()

    // Folder
    let folderX: CGFloat = 230, folderW: CGFloat = 564
    let backTop: CGFloat = 520, bottom: CGFloat = 820
    let back = CGMutablePath()
    back.addRoundedRect(in: CGRect(x: folderX, y: backTop + 40, width: folderW, height: bottom - backTop - 40),
                        cornerWidth: 36, cornerHeight: 36)
    back.addRoundedRect(in: CGRect(x: folderX, y: backTop, width: 220, height: 90), cornerWidth: 30, cornerHeight: 30)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 30, color: color(0x050A20, 0.45))
    ctx.addPath(back)
    ctx.setFillColor(color(0x7E9BE0))
    ctx.fillPath()
    ctx.restoreGState()

    let front = CGPath(roundedRect: CGRect(x: folderX, y: backTop + 92, width: folderW, height: bottom - backTop - 92),
                       cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x0A1430, 0.35))
    ctx.addPath(front)
    ctx.setFillColor(color(0xDCE7FF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(front)
    ctx.clip()
    linearGradient(ctx, [color(0xF4F8FF), color(0xB9CCF5)],
                   from: CGPoint(x: 512, y: backTop + 92), to: CGPoint(x: 512, y: bottom))
    ctx.restoreGState()

    // Subtle top highlight on the body
    linearGradient(ctx, [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)],
                   from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 360))

    ctx.restoreGState()
}

func renderPNG(pixels: Int, to path: String) throws {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // Flip to top-left origin and scale the 1024pt design to the target size
    let scale = CGFloat(pixels) / 1024
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    drawIcon(ctx)

    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot write \(path)"])
    }
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try renderPNG(pixels: size * scale, to: "\(outputDir)/\(name)")
        print("Wrote \(name)")
    }
}
