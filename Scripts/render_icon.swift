import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render_icon source.png output.png\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(data: nil,
                              width: 1024,
                              height: 1024,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("unable to create image context\n", stderr)
    exit(3)
}

context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

// A continuous-curvature superellipse approximates the macOS icon silhouette
// without baking a hard square background into the asset.
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 475
let exponent: CGFloat = 5
let path = CGMutablePath()
for index in 0...512 {
    let angle = CGFloat(index) / 512 * .pi * 2
    let cosine = cos(angle)
    let sine = sin(angle)
    let x = center.x + radius * copysign(pow(abs(cosine), 2 / exponent), cosine)
    let y = center.y + radius * copysign(pow(abs(sine), 2 / exponent), sine)
    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
    else { path.addLine(to: CGPoint(x: x, y: y)) }
}
path.closeSubpath()
context.addPath(path)
context.clip()

let cropInset: CGFloat = 75
let sourceRect = CGRect(x: cropInset,
                        y: cropInset,
                        width: CGFloat(image.width) - cropInset * 2,
                        height: CGFloat(image.height) - cropInset * 2)
guard let cropped = image.cropping(to: sourceRect) else {
    fputs("unable to crop source image\n", stderr)
    exit(4)
}
context.interpolationQuality = .high
context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL,
                                                        UTType.png.identifier as CFString,
                                                        1,
                                                        nil) else {
    fputs("unable to create output\n", stderr)
    exit(5)
}
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("unable to write output\n", stderr)
    exit(6)
}
