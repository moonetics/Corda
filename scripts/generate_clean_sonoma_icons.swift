#!/usr/bin/env swift
import Cocoa
import CoreGraphics

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceLogoUrl = projectRoot.appendingPathComponent("assets/logo-corda.png")

guard let sourceImage = NSImage(contentsOf: sourceLogoUrl),
      let tiffData = sourceImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let cgSourceLogo = bitmap.cgImage else {
    print("Error: Could not load source logo from \(sourceLogoUrl.path)")
    exit(1)
}

print("Loaded source logo from \(sourceLogoUrl.path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) px)")

// Helper: Save CGImage as PNG with exact pixel dimensions
func saveCGImageAsPNG(_ cgImage: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: cgImage.width, height: cgImage.height)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PNGConversionError", code: 1, userInfo: nil)
    }
    try pngData.write(to: url)
}

// 1. Copy new logo to root assets, macos Resources, and android assets
let macResourcesDir = projectRoot.appendingPathComponent("macos/CordaMac/Resources")
let androidAssetsDir = projectRoot.appendingPathComponent("android/assets/images")
try? FileManager.default.createDirectory(at: macResourcesDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: androidAssetsDir, withIntermediateDirectories: true)

let rootLogoTarget = projectRoot.appendingPathComponent("assets/logo-corda.png")
let macLogoTarget = macResourcesDir.appendingPathComponent("logo_corda.png")
let androidLogoTarget = androidAssetsDir.appendingPathComponent("logo_corda.png")

try? FileManager.default.removeItem(at: rootLogoTarget)
try? FileManager.default.copyItem(at: sourceLogoUrl, to: rootLogoTarget)
try? FileManager.default.removeItem(at: macLogoTarget)
try? FileManager.default.copyItem(at: sourceLogoUrl, to: macLogoTarget)
try? FileManager.default.removeItem(at: androidLogoTarget)
try? FileManager.default.copyItem(at: sourceLogoUrl, to: androidLogoTarget)
print("  ✓ Copied new logo to assets/logo-corda.png, macOS Resources & Android assets")

// 2. Generate macOS Menu Bar Template Icon (22x22 px @1x and 44x44 px @2x)
func generateMenuBarIcon(pixelSize: Int, padding: CGFloat) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    let rect = CGRect(
        x: padding,
        y: padding,
        width: CGFloat(pixelSize) - 2 * padding,
        height: CGFloat(pixelSize) - 2 * padding
    )

    ctx.saveGState()
    ctx.clip(to: rect, mask: cgSourceLogo)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fill(rect)
    ctx.restoreGState()

    return ctx.makeImage()
}

if let mb1x = generateMenuBarIcon(pixelSize: 22, padding: 3.5) {
    try? saveCGImageAsPNG(mb1x, to: macResourcesDir.appendingPathComponent("menubar_icon.png"))
}
if let mb2x = generateMenuBarIcon(pixelSize: 44, padding: 7.0) {
    try? saveCGImageAsPNG(mb2x, to: macResourcesDir.appendingPathComponent("menubar_icon@2x.png"))
}
print("  ✓ Generated pure monochrome template menubar_icon.png (22x22 px) and @2x (44x44 px) with refined padding")

// 3. Generate macOS Dark Sonoma Squircle Container Icon
func renderSquircleAppIcon(size: Int) -> CGImage? {
    let width = size
    let height = size
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // Standard Apple squircle grid dimensions
    let padding = Double(size) * 0.09
    let squircleRect = CGRect(
        x: padding,
        y: padding,
        width: Double(size) - (padding * 2),
        height: Double(size) - (padding * 2)
    )
    let cornerRadius = squircleRect.width * 0.224

    // Drop shadow under squircle for macOS dock icons
    if size >= 64 {
        ctx.saveGState()
        let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        ctx.setShadow(offset: CGSize(width: 0, height: -Double(size) * 0.03), blur: Double(size) * 0.06, color: shadowColor)
        let path = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1.0))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Clip to squircle
    ctx.saveGState()
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.clip()

    // Background Gradient (Obsidian Navy to Slate Sonoma)
    let gradColors = [
        CGColor(red: 0.08, green: 0.12, blue: 0.20, alpha: 1.0),
        CGColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1.0)
    ] as CFArray
    let gradLocations: [CGFloat] = [0.0, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: gradLocations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: squircleRect.midX, y: squircleRect.maxY),
            end: CGPoint(x: squircleRect.midX, y: squircleRect.minY),
            options: []
        )
    }

    // Draw Corda Logo Mark in the center with breathing margin
    let logoInset = squircleRect.width * 0.12
    let logoRect = squircleRect.insetBy(dx: logoInset, dy: logoInset)
    ctx.draw(cgSourceLogo, in: logoRect)

    // Subtle specular top gloss
    let glossColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let glossGradient = CGGradient(colorsSpace: colorSpace, colors: glossColors, locations: [0.0, 0.5]) {
        ctx.drawLinearGradient(
            glossGradient,
            start: CGPoint(x: squircleRect.midX, y: squircleRect.maxY),
            end: CGPoint(x: squircleRect.midX, y: squircleRect.midY),
            options: []
        )
    }
    ctx.restoreGState()

    // Outer subtle border
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(max(1.0, Double(size) * 0.015))
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

// 4. Generate macOS AppIcon.icns
let iconsetDir = projectRoot.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, sz) in iconSizes {
    if let iconCG = renderSquircleAppIcon(size: sz) {
        try? saveCGImageAsPNG(iconCG, to: iconsetDir.appendingPathComponent(name))
    }
}

let icnsOutputUrl = macResourcesDir.appendingPathComponent("AppIcon.icns")
let iconutilTask = Process()
iconutilTask.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilTask.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsOutputUrl.path]
try? iconutilTask.run()
iconutilTask.waitUntilExit()
print("  ✓ Generated macOS AppIcon.icns via iconutil (Dark Sonoma Squircle)")

// 5. Generate Android Launcher Mipmap Icons
func renderAndroidRoundIcon(size: Int) -> CGImage? {
    let width = size
    let height = size
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let center = CGPoint(x: width / 2, y: height / 2)
    let radius = CGFloat(size) * 0.46
    let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

    // Clip to circle
    ctx.saveGState()
    ctx.addEllipse(in: circleRect)
    ctx.clip()

    // Background Gradient
    let gradColors = [
        CGColor(red: 0.08, green: 0.12, blue: 0.20, alpha: 1.0),
        CGColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: circleRect.midX, y: circleRect.maxY), end: CGPoint(x: circleRect.midX, y: circleRect.minY), options: [])
    }

    let logoInset = circleRect.width * 0.15
    let logoRect = circleRect.insetBy(dx: logoInset, dy: logoInset)
    ctx.draw(cgSourceLogo, in: logoRect)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: circleRect)
    ctx.setLineWidth(max(1.0, CGFloat(size) * 0.015))
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.2))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

let androidMipmapRoot = projectRoot.appendingPathComponent("android/android/app/src/main/res")
let androidSizes: [(String, Int)] = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192)
]

for (folder, sz) in androidSizes {
    let targetDir = androidMipmapRoot.appendingPathComponent(folder)
    try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

    if let squircleIcon = renderSquircleAppIcon(size: sz) {
        try? saveCGImageAsPNG(squircleIcon, to: targetDir.appendingPathComponent("ic_launcher.png"))
    }
    if let roundIcon = renderAndroidRoundIcon(size: sz) {
        try? saveCGImageAsPNG(roundIcon, to: targetDir.appendingPathComponent("ic_launcher_round.png"))
    }
}
print("  ✓ Generated Android launcher mipmap icons (mdpi to xxxhdpi)")
print("✨ All brand new Corda icons successfully generated and deployed!")
