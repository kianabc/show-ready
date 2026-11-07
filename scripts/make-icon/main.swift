// Renders the app icon from code — no design tool, no binary asset in git.
// The artwork lives in Sources/Showready/Services/LogoArt.swift, shared with
// the in-app logo; build-app.sh compiles the two together:
//
//   swiftc scripts/make-icon/main.swift Sources/Showready/Services/LogoArt.swift -o build/make-icon
//   build/make-icon && iconutil -c icns build/Showready.iconset -o Resources/Showready.icns

import AppKit
import CoreGraphics
import Foundation

func render(size: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    LogoArt.draw(in: context, size: CGFloat(size))
    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try! data.write(to: url)
}

let out = URL(fileURLWithPath: "build/Showready.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    guard let one = render(size: size), let two = render(size: size * 2) else {
        fatalError("render failed at \(size)")
    }
    write(one, to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    write(two, to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("wrote \(out.path)")
