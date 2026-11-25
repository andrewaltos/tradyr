// Renders a placeholder 1024×1024 app icon: an SF Symbol caption bubble on a rounded
// gradient tile. Replace with real artwork later: put a 1024×1024 PNG at
// Resources/AppIcon.png and `make icon` builds the .icns from it.
//
//   swift Scripts/make-icon.swift <output.png>

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

let side = 1024.0
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard
    let context = CGContext(
        data: nil,
        width: Int(side),
        height: Int(side),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    fatalError("could not create bitmap context")
}

NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

// macOS icon art sits inset inside its canvas rather than bleeding to the edge.
let inset = side * 0.08
let tile = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let tilePath = CGPath(
    roundedRect: tile,
    cornerWidth: tile.width * 0.22,
    cornerHeight: tile.height * 0.22,
    transform: nil
)

context.saveGState()
context.addPath(tilePath)
context.clip()

let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 0.10, green: 0.72, blue: 0.78, alpha: 1),
        CGColor(srgbRed: 0.10, green: 0.30, blue: 0.62, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: tile.minX, y: tile.maxY),
    end: CGPoint(x: tile.maxX, y: tile.minY),
    options: []
)
context.restoreGState()

let symbolConfig = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .regular)
    .applying(.init(paletteColors: [.white]))

if let symbol = NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig)
{
    let size = symbol.size
    let origin = CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
    symbol.draw(in: CGRect(origin: origin, size: size))
}

// Two caption lines inside the bubble: the source line dim and short, the translation bright and long.
let bar: (CGFloat, CGFloat, CGFloat, CGFloat) -> Void = { x, y, width, alpha in
    let rect = CGRect(x: x, y: y, width: width, height: side * 0.043)
    context.setFillColor(CGColor(srgbRed: 0.10, green: 0.46, blue: 0.70, alpha: alpha))
    context.addPath(CGPath(
        roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    context.fillPath()
}
bar(side * 0.32, side * 0.575, side * 0.27, 0.45)
bar(side * 0.32, side * 0.470, side * 0.36, 1.0)

NSGraphicsContext.current = nil

guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outputPath) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fatalError("could not encode \(outputPath)")
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("could not write \(outputPath)")
}

print("wrote \(outputPath)")
