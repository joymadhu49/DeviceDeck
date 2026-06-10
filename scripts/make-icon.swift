#!/usr/bin/env swift
//
// make-icon.swift — renders the DeviceDeck app icon master (1024x1024 PNG).
//
// Usage: swift scripts/make-icon.swift <output-dir>
// Writes: <output-dir>/icon_1024.png
//

import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <output-dir>\n".utf8))
    exit(64)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let outputURL = outputDir.appendingPathComponent("icon_1024.png")

let canvasSize = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("error: could not create bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("error: could not create graphics context\n".utf8))
    exit(1)
}
NSGraphicsContext.current = context
context.imageInterpolation = .high

// ---------------------------------------------------------------------------
// Geometry: macOS Big Sur+ squircle — inset 100px, radius ~185.
// ---------------------------------------------------------------------------
let canvas = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
let squircleRect = canvas.insetBy(dx: 100, dy: 100)
let cornerRadius: CGFloat = 185
func squirclePath() -> NSBezierPath {
    NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
}

// ---------------------------------------------------------------------------
// Drop shadow + base fill.
// ---------------------------------------------------------------------------
NSGraphicsContext.current?.saveGraphicsState()
let dropShadow = NSShadow()
dropShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
dropShadow.shadowBlurRadius = 24
dropShadow.shadowOffset = NSSize(width: 0, height: -12)
dropShadow.set()
NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.45, alpha: 1.0).setFill()
squirclePath().fill()
NSGraphicsContext.current?.restoreGraphicsState()

// ---------------------------------------------------------------------------
// Vertical gradient: deep indigo (bottom) -> vivid blue (top).
// ---------------------------------------------------------------------------
let bottomColor = NSColor(calibratedRed: 0.106, green: 0.165, blue: 0.420, alpha: 1.0) // ~#1B2A6B
let midColor    = NSColor(calibratedRed: 0.165, green: 0.310, blue: 0.760, alpha: 1.0)
let topColor    = NSColor(calibratedRed: 0.239, green: 0.482, blue: 1.000, alpha: 1.0) // ~#3D7BFF
if let gradient = NSGradient(colors: [bottomColor, midColor, topColor], atLocations: [0.0, 0.55, 1.0], colorSpace: .genericRGB) {
    gradient.draw(in: squirclePath(), angle: 90)
}

// ---------------------------------------------------------------------------
// Subtle top highlight for depth, clipped to the squircle.
// ---------------------------------------------------------------------------
NSGraphicsContext.current?.saveGraphicsState()
squirclePath().addClip()
if let highlight = NSGradient(
    starting: NSColor.white.withAlphaComponent(0.10),
    ending: NSColor.white.withAlphaComponent(0.0)
) {
    let topThird = NSRect(
        x: squircleRect.minX,
        y: squircleRect.maxY - squircleRect.height * 0.38,
        width: squircleRect.width,
        height: squircleRect.height * 0.38
    )
    highlight.draw(in: topThird, angle: -90)
}
NSGraphicsContext.current?.restoreGraphicsState()

// ---------------------------------------------------------------------------
// Inner border: faint white stroke just inside the edge.
// ---------------------------------------------------------------------------
NSGraphicsContext.current?.saveGraphicsState()
squirclePath().addClip()
let borderPath = NSBezierPath(
    roundedRect: squircleRect.insetBy(dx: 1.5, dy: 1.5),
    xRadius: cornerRadius - 1.5,
    yRadius: cornerRadius - 1.5
)
borderPath.lineWidth = 3
NSColor.white.withAlphaComponent(0.15).setStroke()
borderPath.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

// ---------------------------------------------------------------------------
// Glyph: SF Symbol, hierarchical white, centered (optical shift up ~10px).
// ---------------------------------------------------------------------------
let symbolCandidates = ["macbook.and.iphone", "laptopcomputer.and.iphone", "desktopcomputer"]
var glyph: NSImage?
for name in symbolCandidates {
    if let base = NSImage(systemSymbolName: name, accessibilityDescription: "DeviceDeck") {
        let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .medium)
            .applying(.init(hierarchicalColor: .white))
        glyph = base.withSymbolConfiguration(config)
        if glyph != nil { break }
    }
}

if let glyph {
    let glyphSize = glyph.size
    let targetWidth = squircleRect.width * 0.60
    let scale = targetWidth / max(glyphSize.width, 1)
    let drawSize = NSSize(width: glyphSize.width * scale, height: glyphSize.height * scale)
    let drawRect = NSRect(
        x: squircleRect.midX - drawSize.width / 2,
        y: squircleRect.midY - drawSize.height / 2 - 10,
        width: drawSize.width,
        height: drawSize.height
    )

    NSGraphicsContext.current?.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    glyphShadow.shadowBlurRadius = 12
    glyphShadow.shadowOffset = NSSize(width: 0, height: -6)
    glyphShadow.set()
    glyph.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.current?.restoreGraphicsState()
} else {
    FileHandle.standardError.write(Data("warning: no SF Symbol resolved; icon has no glyph\n".utf8))
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("error: could not encode PNG\n".utf8))
    exit(1)
}
do {
    try png.write(to: outputURL)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
print("Wrote \(outputURL.path)")
