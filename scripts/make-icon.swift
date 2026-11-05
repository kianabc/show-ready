#!/usr/bin/env swift
// Renders Showready.icns from code — no design tool, no binary asset in git.
//
//   swift scripts/make-icon.swift
//   iconutil -c icns build/Showready.iconset -o Resources/Showready.icns
//
// The mark is a white house against a twilight sky — the edit the app is
// best known for.

import AppKit
import CoreGraphics
import Foundation

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons sit inside the canvas rather than filling it; roughly 10%
    // padding with a ~22% corner radius matches the system look.
    let inset = s * 0.094
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow, scaled so small sizes don't turn to mud.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012),
        blur: s * 0.03,
        color: NSColor.black.withAlphaComponent(0.28).cgColor
    )
    context.addPath(squircle)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Twilight sky: deep indigo above, warm orange at the horizon.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let colors = [
        NSColor(srgbRed: 0.10, green: 0.12, blue: 0.35, alpha: 1).cgColor,
        NSColor(srgbRed: 0.36, green: 0.22, blue: 0.50, alpha: 1).cgColor,
        NSColor(srgbRed: 0.95, green: 0.52, blue: 0.25, alpha: 1).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 0.62, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }

    // The house: a simple gable silhouette with lit windows.
    let w = rect.width
    let baseY = rect.minY + w * 0.18
    let bodyW = w * 0.46
    let bodyH = w * 0.26
    let bodyX = rect.midX - bodyW / 2
    let roofPeak = CGPoint(x: rect.midX, y: baseY + bodyH + w * 0.20)

    let house = CGMutablePath()
    house.move(to: CGPoint(x: bodyX, y: baseY))
    house.addLine(to: CGPoint(x: bodyX, y: baseY + bodyH))
    house.addLine(to: CGPoint(x: bodyX - w * 0.045, y: baseY + bodyH))
    house.addLine(to: roofPeak)
    house.addLine(to: CGPoint(x: bodyX + bodyW + w * 0.045, y: baseY + bodyH))
    house.addLine(to: CGPoint(x: bodyX + bodyW, y: baseY + bodyH))
    house.addLine(to: CGPoint(x: bodyX + bodyW, y: baseY))
    house.closeSubpath()

    context.setFillColor(NSColor.white.cgColor)
    context.addPath(house)
    context.fillPath()

    // Two warm windows — the "lights on" edit.
    context.setFillColor(NSColor(srgbRed: 1.0, green: 0.72, blue: 0.30, alpha: 1).cgColor)
    let winW = w * 0.09, winH = w * 0.105
    let winY = baseY + bodyH * 0.28
    context.fill(CGRect(x: rect.midX - w * 0.14, y: winY, width: winW, height: winH))
    context.fill(CGRect(x: rect.midX + w * 0.05, y: winY, width: winW, height: winH))

    context.restoreGState()
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
