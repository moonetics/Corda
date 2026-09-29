import Cocoa
import CoreGraphics

func generateAndroidAdaptiveIcons() {
    let sourcePath = "assets/corda_logo_icon.png"
    guard let sourceImage = NSImage(contentsOfFile: sourcePath),
          let tiffData = sourceImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmap.cgImage else {
        print("Error: Could not load \(sourcePath)")
        exit(1)
    }

    let resBase = "android/android/app/src/main/res"

    // Adaptive icon foreground sizes (108 dp base):
    // mdpi: 108x108
    // hdpi: 162x162
    // xhdpi: 216x216
    // xxhdpi: 324x324
    // xxxhdpi: 432x432
    let adaptiveDensities: [(String, Int)] = [
        ("mipmap-mdpi", 108),
        ("mipmap-hdpi", 162),
        ("mipmap-xhdpi", 216),
        ("mipmap-xxhdpi", 324),
        ("mipmap-xxxhdpi", 432),
    ]

    // Legacy icon sizes (48 dp base):
    // mdpi: 48x48
    // hdpi: 72x72
    // xhdpi: 96x96
    // xxhdpi: 144x144
    // xxxhdpi: 192x192
    let legacyDensities: [(String, Int)] = [
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ]

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    // 1. Generate Adaptive Icon Foreground (Transparent background, bold logo filling ~75% safe zone)
    for (folder, size) in adaptiveDensities {
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { continue }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // Sizing: In adaptive icons (108dp canvas), the safe visible mask is 66-72dp.
        // To make the logo look prominent, full, and not tiny:
        // We set the logo size to ~70% of the canvas (approx 76dp).
        let logoSize = Double(size) * 0.72
        let origin = (Double(size) - logoSize) / 2.0
        let logoRect = CGRect(x: origin, y: origin, width: logoSize, height: logoSize)

        ctx.draw(cgImage, in: logoRect)

        if let outCG = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: outCG)
            rep.size = NSSize(width: size, height: size)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                let path = "\(resBase)/\(folder)/ic_launcher_foreground.png"
                try? pngData.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    // 2. Generate Legacy Full-Bleed Icons (ic_launcher.png and ic_launcher_round.png)
    for (folder, size) in legacyDensities {
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { continue }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius = Double(size) * 0.224
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        // Background Gradient
        let gradColors = [
            CGColor(red: 0.08, green: 0.13, blue: 0.22, alpha: 1.0),
            CGColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1.0)
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
        }

        // Draw Corda Logo full bleed with minimal padding (~8% inset)
        let inset = Double(size) * 0.08
        let logoRect = rect.insetBy(dx: inset, dy: inset)
        ctx.draw(cgImage, in: logoRect)

        ctx.restoreGState()

        // Border
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(max(1.0, Double(size) * 0.02))
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15))
        ctx.strokePath()
        ctx.restoreGState()

        if let outCG = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: outCG)
            rep.size = NSSize(width: size, height: size)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                let outPath = "\(resBase)/\(folder)/ic_launcher.png"
                let roundPath = "\(resBase)/\(folder)/ic_launcher_round.png"
                try? pngData.write(to: URL(fileURLWithPath: outPath))
                try? pngData.write(to: URL(fileURLWithPath: roundPath))
            }
        }
    }

    print("Successfully generated all Android Adaptive & Legacy icons!")
}

generateAndroidAdaptiveIcons()
