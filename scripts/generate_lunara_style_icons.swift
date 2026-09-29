import Cocoa
import CoreGraphics

func generateLunaraStyleIcons() {
    let sourcePath = "corda_without_text.png"
    guard let sourceImage = NSImage(contentsOfFile: sourcePath),
          let tiffData = sourceImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmap.cgImage else {
        print("Error: Could not load \(sourcePath)")
        exit(1)
    }

    // The blue squircle in corda_without_text.png (1254x1254) is located at:
    // x: 166 to 1087, y: 160 to 1069 (approx 922 x 910 px)
    // In CoreGraphics (origin bottom-left), y needs to be calculated:
    let cropRect = CGRect(x: 166, y: 1254 - 1069, width: 922, height: 910)
    guard let croppedCG = cgImage.cropping(to: cropRect) else {
        print("Error: Could not crop image")
        exit(1)
    }

    // Remove white background outside the squircle and make transparent
    let cropW = croppedCG.width
    let cropH = croppedCG.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let ctx = CGContext(
        data: nil,
        width: cropW,
        height: cropH,
        bitsPerComponent: 8,
        bytesPerRow: cropW * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        print("Error: Could not create context")
        exit(1)
    }

    ctx.draw(croppedCG, in: CGRect(x: 0, y: 0, width: cropW, height: cropH))

    guard let pixelData = ctx.data else { exit(1) }
    let buffer = pixelData.bindMemory(to: UInt8.self, capacity: cropW * cropH * 4)

    // Alpha processing: detect white background on corners and make transparent
    for y in 0..<cropH {
        for x in 0..<cropW {
            let offset = (y * cropW + x) * 4
            let r = Float(buffer[offset])
            let g = Float(buffer[offset + 1])
            let b = Float(buffer[offset + 2])

            // If pixel is white / light halo (> 240)
            if r > 240 && g > 240 && b > 240 {
                buffer[offset + 3] = 0
            } else if r > 220 && g > 220 && b > 220 {
                // Anti-aliased edge feathering
                let brightness = (r + g + b) / 3.0
                let alpha = (240.0 - brightness) / 20.0
                buffer[offset + 3] = UInt8(clamping: Int(alpha * 255.0))
            }
        }
    }

    guard let transparentSquircle = ctx.makeImage() else { exit(1) }

    // Densities matching Lunara (/Users/percayajanji/Documents/Mens):
    let densities: [(String, Int)] = [
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ]

    let resBase = "android/android/app/src/main/res"

    for (folder, size) in densities {
        guard let outCtx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { continue }

        outCtx.setAllowsAntialiasing(true)
        outCtx.setShouldAntialias(true)
        outCtx.interpolationQuality = .high

        // Just like Lunara (94-96% fill):
        let targetSize = Double(size) * 0.96
        let origin = (Double(size) - targetSize) / 2.0
        let drawRect = CGRect(x: origin, y: origin, width: targetSize, height: targetSize)

        outCtx.draw(transparentSquircle, in: drawRect)

        if let finalCG = outCtx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: finalCG)
            rep.size = NSSize(width: size, height: size)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                let outPath = "\(resBase)/\(folder)/ic_launcher.png"
                try? pngData.write(to: URL(fileURLWithPath: outPath))
                print("Saved \(outPath) (\(size)x\(size))")
            }
        }
    }

    // Also update assets/corda_logo_icon.png and macos/CordaMac/Resources
    let masterSize = 1024
    if let masterCtx = CGContext(
        data: nil,
        width: masterSize,
        height: masterSize,
        bitsPerComponent: 8,
        bytesPerRow: masterSize * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) {
        masterCtx.setAllowsAntialiasing(true)
        masterCtx.setShouldAntialias(true)
        masterCtx.interpolationQuality = .high
        masterCtx.draw(transparentSquircle, in: CGRect(x: 0, y: 0, width: masterSize, height: masterSize))
        if let masterCG = masterCtx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: masterCG)
            rep.size = NSSize(width: masterSize, height: masterSize)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: "assets/corda_logo_icon.png"))
                try? pngData.write(to: URL(fileURLWithPath: "android/assets/images/corda_logo_icon.png"))
                try? pngData.write(to: URL(fileURLWithPath: "macos/CordaMac/Resources/corda_logo_icon.png"))
            }
        }
    }

    print("Lunara-style icon generation complete!")
}

generateLunaraStyleIcons()
