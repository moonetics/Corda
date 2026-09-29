#!/usr/bin/env swift
import Cocoa
import CoreGraphics

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceLogoUrl = projectRoot.appendingPathComponent("assets/logo-corda.png")

guard let sourceImage = NSImage(contentsOf: sourceLogoUrl) else {
    print("Error: Could not load source logo from \(sourceLogoUrl.path)")
    exit(1)
}

print("Loaded source logo from \(sourceLogoUrl.path) (\(sourceImage.size.width)x\(sourceImage.size.height))")

// Helper: Save NSImage as PNG
func savePNG(image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PNGConversionError", code: 1, userInfo: nil)
    }
    try pngData.write(to: url)
}

// 1. Copy logo_corda.png to macos Resources and android assets
let macResourcesDir = projectRoot.appendingPathComponent("macos/CordaMac/Resources")
let androidAssetsDir = projectRoot.appendingPathComponent("android/assets/images")
try? FileManager.default.createDirectory(at: macResourcesDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: androidAssetsDir, withIntermediateDirectories: true)

let macLogoTarget = macResourcesDir.appendingPathComponent("logo_corda.png")
let androidLogoTarget = androidAssetsDir.appendingPathComponent("logo_corda.png")

try? FileManager.default.removeItem(at: macLogoTarget)
try? FileManager.default.copyItem(at: sourceLogoUrl, to: macLogoTarget)
try? FileManager.default.removeItem(at: androidLogoTarget)
try? FileManager.default.copyItem(at: sourceLogoUrl, to: androidLogoTarget)
print("  ✓ Copied canonical logo_corda.png to macOS Resources & Android assets")

// 2. Generate macOS Menu Bar Template Icon (18x18 @1x and 36x36 @2x)
func generateMenuBarIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }
    
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    
    let padding: CGFloat = size > 24 ? 3.0 : 1.5
    let rect = CGRect(x: padding, y: padding, width: size - 2 * padding, height: size - 2 * padding)
    
    // Draw source logo as monochrome silhouette
    if let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.saveGState()
        ctx.clip(to: rect, mask: cgImage)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(rect)
        ctx.restoreGState()
    }
    
    img.unlockFocus()
    img.isTemplate = true
    return img
}

let menuBar1x = generateMenuBarIcon(size: 18)
let menuBar2x = generateMenuBarIcon(size: 36)
try? savePNG(image: menuBar1x, to: macResourcesDir.appendingPathComponent("menubar_icon.png"))
try? savePNG(image: menuBar2x, to: macResourcesDir.appendingPathComponent("menubar_icon@2x.png"))
print("  ✓ Generated pure monochrome template menubar_icon.png (18x18) and @2x (36x36)")

// 3. Generate macOS AppIcon.icns
func generateMacSquircleIcon(dimension: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: dimension, height: dimension))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }
    
    ctx.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))
    
    let cornerRadius = dimension * 0.225
    let squircleRect = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    let path = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    
    let colors = [
        NSColor(red: 0.086, green: 0.094, blue: 0.114, alpha: 1.0).cgColor,
        NSColor(red: 0.063, green: 0.071, blue: 0.086, alpha: 1.0).cgColor
    ] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: dimension), end: CGPoint(x: 0, y: 0), options: [])
    }
    
    let margin = dimension * 0.15
    let logoRect = CGRect(x: margin, y: margin, width: dimension - 2 * margin, height: dimension - 2 * margin)
    if let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cgImage, in: logoRect)
    }
    
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
    ctx.setLineWidth(max(1.0, dimension * 0.012))
    ctx.strokePath()
    
    ctx.restoreGState()
    img.unlockFocus()
    return img
}

let iconsetDir = projectRoot.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
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
    let iconImg = generateMacSquircleIcon(dimension: sz)
    try? savePNG(image: iconImg, to: iconsetDir.appendingPathComponent(name))
}

let icnsOutputUrl = macResourcesDir.appendingPathComponent("AppIcon.icns")
let iconutilTask = Process()
iconutilTask.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilTask.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsOutputUrl.path]
try? iconutilTask.run()
iconutilTask.waitUntilExit()
print("  ✓ Generated macOS AppIcon.icns via iconutil")

// 4. Generate Android Launcher Mipmap Icons
let androidMipmapRoot = projectRoot.appendingPathComponent("android/android/app/src/main/res")
let androidSizes: [(String, CGFloat)] = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192)
]

for (folder, sz) in androidSizes {
    let targetDir = androidMipmapRoot.appendingPathComponent(folder)
    try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
    
    let squircleIcon = generateMacSquircleIcon(dimension: sz)
    try? savePNG(image: squircleIcon, to: targetDir.appendingPathComponent("ic_launcher.png"))
    try? savePNG(image: squircleIcon, to: targetDir.appendingPathComponent("ic_launcher_round.png"))
}
print("  ✓ Generated Android launcher mipmap icons (mdpi to xxxhdpi)")
print("✨ All Clean Sonoma icons successfully created!")
