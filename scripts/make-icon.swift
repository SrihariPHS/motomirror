#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Darwin
import Foundation

let canvasSize = 1024
let canvas = CGFloat(canvasSize)

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func outputURL() -> URL {
    if CommandLine.arguments.count > 1 {
        let expanded = NSString(string: CommandLine.arguments[1]).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
    let scriptURL = URL(fileURLWithPath: #filePath)
    let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Resources/AppIcon-1024.png")
}

func squirclePath(center: CGPoint, halfWidth: CGFloat, halfHeight: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let segments = 720
    let exponent = 5.0
    for index in 0...segments {
        let angle = Double(index) / Double(segments) * 2.0 * Double.pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = Double(center.x) + Double(halfWidth) * copysign(pow(abs(cosine), 2.0 / exponent), cosine)
        let y = Double(center.y) + Double(halfHeight) * copysign(pow(abs(sine), 2.0 / exponent), sine)
        let point = CGPoint(x: x, y: y)
        if index == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
}

func strokeArc(
    _ context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    startDegrees: CGFloat,
    endDegrees: CGFloat,
    lineWidth: CGFloat,
    color: CGColor
) {
    context.saveGState()
    context.setShadow(offset: .zero, blur: 30, color: color.copy(alpha: 0.55))
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.addArc(
        center: center,
        radius: radius,
        startAngle: startDegrees * .pi / 180,
        endAngle: endDegrees * .pi / 180,
        clockwise: false
    )
    context.strokePath()
    context.restoreGState()
}

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    die("could not create the sRGB color space")
}
guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    die("could not create the drawing context")
}

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

let iconPath = squirclePath(center: CGPoint(x: canvas / 2, y: canvas / 2), halfWidth: 462, halfHeight: 462)
let center = CGPoint(x: canvas / 2, y: canvas / 2)

let indigoTop = CGColor(srgbRed: 0.18, green: 0.11, blue: 0.44, alpha: 1.0)
let indigoBottom = CGColor(srgbRed: 0.06, green: 0.04, blue: 0.18, alpha: 1.0)
let mint = CGColor(srgbRed: 0.63, green: 0.96, blue: 0.80, alpha: 1.0)
let white = CGColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 1.0)

if let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [indigoTop, indigoBottom] as CFArray,
    locations: [0.0, 1.0]
) {
    context.saveGState()
    context.addPath(iconPath)
    context.clip()
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: center.x, y: canvas),
        end: CGPoint(x: center.x, y: 0),
        options: []
    )
    context.restoreGState()
}

context.saveGState()
context.addPath(iconPath)
context.clip()

if let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.45, green: 0.91, blue: 0.73, alpha: 0.20),
        CGColor(srgbRed: 0.45, green: 0.91, blue: 0.73, alpha: 0.0),
    ] as CFArray,
    locations: [0.0, 1.0]
) {
    context.drawRadialGradient(
        glow,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: 470,
        options: []
    )
}

for (radius, width, alpha) in [(318.0, 17.0, 0.34), (392.0, 15.0, 0.20)] as [(CGFloat, CGFloat, CGFloat)] {
    let color = mint.copy(alpha: alpha) ?? mint
    strokeArc(context, center: center, radius: radius, startDegrees: 140, endDegrees: 220, lineWidth: width, color: color)
    strokeArc(context, center: center, radius: radius, startDegrees: -40, endDegrees: 40, lineWidth: width, color: color)
}

let phoneRect = CGRect(x: 347, y: 197, width: 330, height: 630)
let phonePath = CGPath(roundedRect: phoneRect, cornerWidth: 74, cornerHeight: 74, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 42, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.38))
context.setFillColor(white)
context.addPath(phonePath)
context.fillPath()
context.restoreGState()

let screenRect = phoneRect.insetBy(dx: 25, dy: 25)
let screenPath = CGPath(roundedRect: screenRect, cornerWidth: 51, cornerHeight: 51, transform: nil)

let mintTop = CGColor(srgbRed: 0.76, green: 1.0, blue: 0.88, alpha: 1.0)
let mintBottom = CGColor(srgbRed: 0.43, green: 0.88, blue: 0.69, alpha: 1.0)
if let screenGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [mintTop, mintBottom] as CFArray,
    locations: [0.0, 1.0]
) {
    context.saveGState()
    context.addPath(screenPath)
    context.clip()
    context.drawLinearGradient(
        screenGradient,
        start: CGPoint(x: screenRect.midX, y: screenRect.maxY),
        end: CGPoint(x: screenRect.midX, y: screenRect.minY),
        options: []
    )
    context.restoreGState()
}

context.saveGState()
context.addPath(screenPath)
context.clip()
let highlight = CGMutablePath()
highlight.move(to: CGPoint(x: screenRect.minX - 40, y: screenRect.minY + 120))
highlight.addLine(to: CGPoint(x: screenRect.midX + 70, y: screenRect.maxY + 80))
highlight.addLine(to: CGPoint(x: screenRect.midX + 170, y: screenRect.maxY + 80))
highlight.addLine(to: CGPoint(x: screenRect.minX + 60, y: screenRect.minY + 120))
highlight.closeSubpath()
context.setFillColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.14))
context.addPath(highlight)
context.fillPath()
context.restoreGState()

context.addPath(iconPath)
context.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.12))
context.setLineWidth(8)
context.strokePath()

context.restoreGState()

guard let image = context.makeImage() else {
    die("could not create the final image")
}

let destination = outputURL()
do {
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
} catch {
    die("could not create output directory: \(error.localizedDescription)")
}

let bitmap = NSBitmapImageRep(cgImage: image)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    die("could not encode the icon as PNG")
}

do {
    try pngData.write(to: destination, options: .atomic)
} catch {
    die("could not write \(destination.path): \(error.localizedDescription)")
}

print("Wrote \(destination.path) (\(canvasSize)x\(canvasSize))")
