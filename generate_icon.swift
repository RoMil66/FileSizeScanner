import Cocoa
import CoreGraphics

// Generate FileSizeScanner app icon at multiple sizes
func generateIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let s = size
    let padding = s * 0.08
    let cornerRadius = s * 0.22
    
    // Background gradient (very dark for high contrast/glow)
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(srgbRed: 0.03, green: 0.03, blue: 0.10, alpha: 1.0),
        CGColor(srgbRed: 0.07, green: 0.04, blue: 0.18, alpha: 1.0),
        CGColor(srgbRed: 0.04, green: 0.06, blue: 0.14, alpha: 1.0)
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Subtle center bloom to add depth
    let bloomColors = [
        CGColor(srgbRed: 0.35, green: 0.20, blue: 0.70, alpha: 0.30),
        CGColor(srgbRed: 0.0,  green: 0.0,  blue: 0.0,  alpha: 0.0)
    ] as CFArray
    let bloomGrad = CGGradient(colorsSpace: colorSpace, colors: bloomColors, locations: [0, 1])!
    ctx.drawRadialGradient(bloomGrad,
        startCenter: CGPoint(x: s * 0.50, y: s * 0.52), startRadius: 0,
        endCenter:   CGPoint(x: s * 0.50, y: s * 0.52), endRadius: s * 0.65,
        options: [.drawsAfterEndLocation])
    
    // Treemap blocks
    struct Block {
        let rect: CGRect
        let r: CGFloat, g: CGFloat, b: CGFloat
    }
    
    let inset = padding * 1.5
    let w = s - inset * 2
    let h = s - inset * 2
    let ox = inset
    let oy = inset
    
    // Treemap layout — larger blocks represent bigger folders
    let gap: CGFloat = s * 0.015
    
    let blocks: [Block] = [
        // Large block top-left — electric blue
        Block(rect: CGRect(x: ox, y: oy + h * 0.45 + gap/2, width: w * 0.45 - gap/2, height: h * 0.55 - gap/2),
              r: 0.15, g: 0.55, b: 1.00),
        // Medium block top-right — vivid green
        Block(rect: CGRect(x: ox + w * 0.45 + gap/2, y: oy + h * 0.65 + gap/2, width: w * 0.55 - gap/2, height: h * 0.35 - gap/2),
              r: 0.10, g: 0.95, b: 0.55),
        // Medium block middle-right top — bright orange
        Block(rect: CGRect(x: ox + w * 0.45 + gap/2, y: oy + h * 0.35 + gap/2, width: w * 0.30 - gap/2, height: h * 0.30 - gap/2),
              r: 1.00, g: 0.55, b: 0.05),
        // Small block middle-right bottom — hot pink
        Block(rect: CGRect(x: ox + w * 0.75 + gap/2, y: oy + h * 0.35 + gap/2, width: w * 0.25 - gap/2, height: h * 0.30 - gap/2),
              r: 1.00, g: 0.20, b: 0.45),
        // Bottom strip left — vivid purple
        Block(rect: CGRect(x: ox, y: oy, width: w * 0.30 - gap/2, height: h * 0.45 - gap/2),
              r: 0.68, g: 0.25, b: 1.00),
        // Bottom strip middle — neon cyan
        Block(rect: CGRect(x: ox + w * 0.30 + gap/2, y: oy, width: w * 0.25 - gap/2, height: h * 0.35 - gap/2),
              r: 0.00, g: 0.88, b: 1.00),
        // Bottom strip right — bright yellow-gold
        Block(rect: CGRect(x: ox + w * 0.55 + gap/2, y: oy, width: w * 0.45 - gap/2, height: h * 0.35 - gap/2),
              r: 1.00, g: 0.85, b: 0.02),
    ]
    
    for block in blocks {
        let rect = block.rect
        let bPath = CGPath(roundedRect: rect, cornerWidth: s * 0.03, cornerHeight: s * 0.03, transform: nil)

        // Outer glow pass — colored shadow bleeds outside the block
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.07,
                      color: CGColor(srgbRed: block.r, green: block.g, blue: block.b, alpha: 0.90))
        ctx.setFillColor(CGColor(srgbRed: block.r, green: block.g, blue: block.b, alpha: 1.0))
        ctx.addPath(bPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Gradient pass — bright-to-vivid, clipped to block shape
        ctx.saveGState()
        ctx.addPath(bPath)
        ctx.clip()

        let c1 = CGColor(srgbRed: min(block.r + 0.20, 1.0), green: min(block.g + 0.20, 1.0), blue: min(block.b + 0.20, 1.0), alpha: 1.0)
        let c2 = CGColor(srgbRed: block.r * 0.70, green: block.g * 0.70, blue: block.b * 0.70, alpha: 1.0)
        let blockGrad = CGGradient(colorsSpace: colorSpace, colors: [c1, c2] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(blockGrad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

        // Strong inner highlight rim
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.40))
        ctx.setLineWidth(s * 0.006)
        ctx.addPath(bPath)
        ctx.strokePath()

        ctx.restoreGState()
    }
    
    // Magnifying glass overlay (bottom-right)
    let glassSize = s * 0.38
    let glassCenterX = s * 0.72
    let glassCenterY = s * 0.28
    let glassRadius = glassSize * 0.35
    
    // Glass shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.04, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
    
    // Handle
    let handleAngle: CGFloat = -.pi / 4
    let handleStart = CGPoint(
        x: glassCenterX + glassRadius * 0.75 * cos(handleAngle),
        y: glassCenterY + glassRadius * 0.75 * sin(handleAngle)
    )
    let handleEnd = CGPoint(
        x: glassCenterX + glassSize * 0.52 * cos(handleAngle),
        y: glassCenterY + glassSize * 0.52 * sin(handleAngle)
    )
    
    ctx.setLineCap(.round)
    ctx.setLineWidth(s * 0.045)
    ctx.setStrokeColor(CGColor(srgbRed: 0.75, green: 0.78, blue: 0.82, alpha: 1.0))
    ctx.move(to: handleStart)
    ctx.addLine(to: handleEnd)
    ctx.strokePath()
    
    // Handle highlight
    ctx.setLineWidth(s * 0.02)
    ctx.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.92, blue: 0.95, alpha: 1.0))
    ctx.move(to: handleStart)
    ctx.addLine(to: handleEnd)
    ctx.strokePath()
    
    // Glass circle - outer ring
    ctx.setLineWidth(s * 0.03)
    ctx.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.88, blue: 0.92, alpha: 1.0))
    ctx.addEllipse(in: CGRect(x: glassCenterX - glassRadius, y: glassCenterY - glassRadius, width: glassRadius * 2, height: glassRadius * 2))
    ctx.strokePath()
    
    // Glass fill — semi-transparent
    ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.93, blue: 1.0, alpha: 0.2))
    ctx.addEllipse(in: CGRect(x: glassCenterX - glassRadius, y: glassCenterY - glassRadius, width: glassRadius * 2, height: glassRadius * 2))
    ctx.fillPath()
    
    // Glass shine
    let shineRadius = glassRadius * 0.7
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25))
    ctx.setLineWidth(s * 0.012)
    ctx.addArc(center: CGPoint(x: glassCenterX - glassRadius * 0.15, y: glassCenterY + glassRadius * 0.15),
               radius: shineRadius, startAngle: .pi * 0.3, endAngle: .pi * 0.8, clockwise: false)
    ctx.strokePath()
    
    ctx.restoreGState()
    
    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, path: String, pixelSize: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("Saved: \(path) (\(pixelSize)x\(pixelSize))")
}

// Icon sizes for macOS
let iconSizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1),
    ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1),
    ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1),
    ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1),
    ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1),
    ("icon_512x512@2x", 512, 2),
]

let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let image = generateIcon(size: 1024)

for iconSize in iconSizes {
    let pixels = iconSize.points * iconSize.scale
    let path = "\(basePath)/\(iconSize.name).png"
    savePNG(image: image, path: path, pixelSize: pixels)
}

print("All icons generated!")
