import Cocoa
import CoreGraphics

func generateMacAppIcon() {
    let sourcePath = "assets/corda_logo_icon.png"
    guard let sourceImage = NSImage(contentsOfFile: sourcePath),
          let tiffData = sourceImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmap.cgImage else {
        print("Error: Could not load \(sourcePath)")
        exit(1)
    }

    let iconsetDir = "build/AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: iconsetDir)
    try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    let sizes: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for (filename, size) in sizes {
        let width = size
        let height = size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            print("Failed to create CGContext for size \(size)")
            continue
        }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // Apple squircle dimensions (macOS standard icon grid: ~824px wide inside 1024px canvas)
        let padding = Double(size) * 0.09
        let squircleRect = CGRect(
            x: padding,
            y: padding,
            width: Double(size) - (padding * 2),
            height: Double(size) - (padding * 2)
        )
        let cornerRadius = squircleRect.width * 0.224

        // Draw shadow under squircle for large icons
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

        // Background Gradient (Deep Obsidian Navy to Dark Slate Glass)
        let gradColors = [
            CGColor(red: 0.08, green: 0.13, blue: 0.22, alpha: 1.0),
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

        // Draw Corda Logo Mark in the center
        let logoInset = squircleRect.width * 0.12
        let logoRect = squircleRect.insetBy(dx: logoInset, dy: logoInset)
        ctx.draw(cgImage, in: logoRect)

        // Draw subtle specular top gloss
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

        // Draw continuous border
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.setLineWidth(max(1.0, Double(size) * 0.015))
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.2))
        ctx.strokePath()
        ctx.restoreGState()

        // Save image to file
        guard let outputCGImage = ctx.makeImage() else { continue }
        let rep = NSBitmapImageRep(cgImage: outputCGImage)
        rep.size = NSSize(width: width, height: height)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { continue }

        let outUrl = URL(fileURLWithPath: "\(iconsetDir)/\(filename)")
        try? pngData.write(to: outUrl)
    }

    print("Generated all icons in \(iconsetDir)")
}

generateMacAppIcon()
