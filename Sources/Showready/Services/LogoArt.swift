#if os(macOS)
import AppKit
import CoreGraphics

/// The Rocco Show Ready mark, drawn in code. Shared by the in-app logo and
/// `scripts/make-icon/main.swift` (compiled together), so the app icon and
/// the empty-state logo can never drift apart. Coordinates are y-up.
enum LogoArt {
    static func draw(in ctx: CGContext, size s: CGFloat, shadow: Bool = true) {
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        // macOS icons sit inside the canvas with ~10% padding and a ~22% corner.
        let inset = s * 0.094
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let radius = rect.width * 0.2237
        let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if shadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                          color: NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.addPath(tile)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()

        // Coral → pink → violet → blue, top-left to bottom-right.
        let colors = [
            rgb(1.00, 0.58, 0.40), rgb(0.96, 0.36, 0.55),
            rgb(0.62, 0.33, 0.90), rgb(0.27, 0.45, 0.98),
        ] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                              locations: [0, 0.38, 0.72, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        }

        let w = rect.width
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * w) }

        // Sun, with a soft halo, behind the house.
        ctx.setFillColor(rgb(1.0, 0.86, 0.35, 0.35))
        ctx.fillEllipse(in: circle(p(0.70, 0.66), w * 0.17))
        ctx.setFillColor(rgb(1.0, 0.84, 0.30))
        ctx.fillEllipse(in: circle(p(0.70, 0.66), w * 0.12))

        // Ground: a soft rounded band under the house.
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + w * 0.16, y: rect.minY + w * 0.15,
                                               width: w * 0.68, height: w * 0.05),
                           cornerWidth: w * 0.025, cornerHeight: w * 0.025, transform: nil))
        ctx.fillPath()

        // House: gable silhouette with a little roof overhang.
        let baseY: CGFloat = 0.19, bodyH: CGFloat = 0.27
        let left: CGFloat = 0.27, right: CGFloat = 0.73
        let house = CGMutablePath()
        house.move(to: p(left, baseY))
        house.addLine(to: p(left, baseY + bodyH))
        house.addLine(to: p(left - 0.05, baseY + bodyH))
        house.addLine(to: p(0.50, baseY + bodyH + 0.22))
        house.addLine(to: p(right + 0.05, baseY + bodyH))
        house.addLine(to: p(right, baseY + bodyH))
        house.addLine(to: p(right, baseY))
        house.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.01), blur: w * 0.03,
                      color: NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(house)
        ctx.fillPath()
        ctx.restoreGState()

        // Warm lit windows and a door in the brand violet.
        ctx.setFillColor(rgb(1.0, 0.72, 0.28))
        roundRect(ctx, CGRect(origin: p(0.32, 0.31), size: CGSize(width: w * 0.09, height: w * 0.09)), w * 0.015)
        roundRect(ctx, CGRect(origin: p(0.59, 0.31), size: CGSize(width: w * 0.09, height: w * 0.09)), w * 0.015)
        ctx.setFillColor(rgb(0.55, 0.36, 0.92))
        roundRect(ctx, CGRect(origin: p(0.455, baseY), size: CGSize(width: w * 0.09, height: w * 0.15)), w * 0.02)

        // Sparkles: "show ready".
        ctx.setFillColor(NSColor.white.cgColor)
        sparkle(ctx, center: p(0.25, 0.75), r: w * 0.085)
        sparkle(ctx, center: p(0.36, 0.86), r: w * 0.04)

        ctx.restoreGState()
    }

    /// The mark as an image, for SwiftUI.
    static func image(points: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: points, height: points), flipped: false) { _ in
            if let ctx = NSGraphicsContext.current?.cgContext { draw(in: ctx, size: points) }
            return true
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private static func roundRect(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }

    /// Four-point star with concave sides.
    private static func sparkle(_ ctx: CGContext, center c: CGPoint, r: CGFloat) {
        let k = r * 0.14
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x, y: c.y + r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
}
#endif
