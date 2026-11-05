#if os(macOS)
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import Vision
import ShowreadyCore

enum ImageToolsError: LocalizedError {
    case unreadable(String)
    case encodeFailed
    var errorDescription: String? {
        switch self {
        case .unreadable(let n): return "Could not read \(n)."
        case .encodeFailed: return "Could not encode the image."
        }
    }
}

/// Local image work: loading, resizing, encoding, metadata, free enhancements.
enum ImageTools {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    static let supportedTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .rawImage, .image]

    /// Loads the full image with EXIF orientation applied.
    static func loadCI(_ url: URL) throws -> CIImage {
        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw ImageToolsError.unreadable(url.lastPathComponent)
        }
        return img
    }

    static func pixelSize(_ url: URL) -> PixelSize? {
        guard let img = try? loadCI(url) else { return nil }
        return PixelSize(width: Int(img.extent.width), height: Int(img.extent.height))
    }

    static func thumbnail(_ url: URL, maxEdge: Int = 600) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxEdge]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Scales so the long edge equals `longEdge` (up or down) with Lanczos.
    static func scaled(_ img: CIImage, longEdge: Int) -> CIImage {
        let long = max(img.extent.width, img.extent.height)
        let scale = CGFloat(longEdge) / long
        guard abs(scale - 1) > 0.001 else { return img }
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = img
        f.scale = Float(scale)
        f.aspectRatio = 1
        return f.outputImage ?? img
    }

    /// The part of the source (normalized, top-left origin) that survives a scale-to-fill
    /// and center crop to `target`. Nearly the whole frame for custom-size models.
    static func fillCrop(source: PixelSize, target: PixelSize) -> CGRect {
        let scale = max(CGFloat(target.width) / CGFloat(source.width), CGFloat(target.height) / CGFloat(source.height))
        let fw = CGFloat(target.width) / (CGFloat(source.width) * scale)
        let fh = CGFloat(target.height) / (CGFloat(source.height) * scale)
        return CGRect(x: (1 - fw) / 2, y: (1 - fh) / 2, width: fw, height: fh)
    }

    /// Scales to fill an exact pixel size and center-crops the overflow, so nothing is stretched.
    static func resized(_ img: CIImage, to size: PixelSize) -> CIImage {
        let tw = CGFloat(size.width), th = CGFloat(size.height)
        let scale = max(tw / img.extent.width, th / img.extent.height)
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = img
        f.scale = Float(scale)
        f.aspectRatio = 1
        let out = f.outputImage ?? img
        let x = (out.extent.minX + (out.extent.width - tw) / 2).rounded(.down)
        let y = (out.extent.minY + (out.extent.height - th) / 2).rounded(.down)
        let cropped = out.cropped(to: CGRect(x: x, y: y, width: tw, height: th))
        return cropped.transformed(by: CGAffineTransform(translationX: -x, y: -y))
    }

    /// JPEG with no source metadata (GPS, camera serials, owner names).
    static func jpeg(_ img: CIImage, quality: Double = 0.92) throws -> Data {
        let rect = img.extent.integral
        guard let cg = context.createCGImage(img, from: rect) else { throw ImageToolsError.encodeFailed }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ImageToolsError.encodeFailed }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageToolsError.encodeFailed }
        return data as Data
    }

    static func png(_ img: CIImage) throws -> Data {
        guard let cg = context.createCGImage(img, from: img.extent.integral),
              let d = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { throw ImageToolsError.encodeFailed }
        return d
    }

    /// Prepares the upload: oriented, sRGB, sized to `size`.
    /// PNG when a mask is used, since OpenAI wants the mask and image in the same format.
    static func uploadData(_ url: URL, size: PixelSize, levelHorizon: Bool, asPNG: Bool) throws -> Data {
        var img = try loadCI(url)
        if levelHorizon { img = leveled(img) }
        let sized = resized(img, to: size)
        return asPNG ? try png(sized) : try jpeg(sized, quality: 0.92)
    }

    /// Free, on-device auto enhance: Apple's auto adjustments plus light noise reduction and sharpening.
    static func quickEnhance(_ url: URL, levelHorizon: Bool) throws -> CIImage {
        var img = try loadCI(url)
        if levelHorizon { img = leveled(img) }
        for f in img.autoAdjustmentFilters(options: [.redEye: false]) {
            f.setValue(img, forKey: kCIInputImageKey)
            if let o = f.outputImage { img = o }
        }
        let nr = CIFilter.noiseReduction()
        nr.inputImage = img; nr.noiseLevel = 0.01; nr.sharpness = 0.4
        img = nr.outputImage ?? img
        let sh = CIFilter.unsharpMask()
        sh.inputImage = img; sh.radius = 1.2; sh.intensity = 0.35
        return sh.outputImage ?? img
    }

    /// Rotates by the detected horizon angle, then crops away the empty corners.
    static func leveled(_ img: CIImage) -> CIImage {
        let req = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(ciImage: img)
        guard (try? handler.perform([req])) != nil,
              let angle = req.results?.first?.angle,
              abs(angle) > 0.002, abs(angle) < 0.12 else { return img }
        let f = CIFilter.straightenFilter()
        f.inputImage = img
        f.angle = Float(-angle)
        return f.outputImage?.cropped(to: img.extent) ?? img
    }

    /// Writes the final file at the chosen long edge with metadata stripped.
    static func export(_ resultURL: URL, to dest: URL, longEdge: Int?) throws {
        var img = try loadCI(resultURL)
        if let longEdge { img = scaled(img, longEdge: longEdge) }
        try jpeg(img, quality: 0.93).write(to: dest, options: .atomic)
    }

    /// Guesses interior vs exterior with Apple's on-device classifier.
    static func guessKind(_ url: URL) -> PhotoKind {
        guard let thumb = thumbnail(url, maxEdge: 512),
              let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .interior }
        let req = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: cg).perform([req])) != nil,
              let results = req.results else { return .interior }
        let outdoor = ["sky", "outdoor", "lawn", "yard", "grass", "tree", "house_single", "roof", "garden", "driveway", "cloud"]
        let indoor = ["indoor", "room", "kitchen", "bathroom", "bedroom", "living_room", "furniture", "sofa", "interior_room", "ceiling"]
        var o = 0.0, i = 0.0
        for r in results where r.confidence > 0.1 {
            let id = r.identifier.lowercased()
            if outdoor.contains(where: { id.contains($0) }) { o += Double(r.confidence) }
            if indoor.contains(where: { id.contains($0) }) { i += Double(r.confidence) }
        }
        return o > i ? .exterior : .interior
    }
}

/// A brush stroke in normalized image coordinates (0...1, origin top-left).
struct MaskStroke: Equatable, Codable {
    var points: [CGPoint]
    var radius: CGFloat   // fraction of image width
}

enum MaskRenderer {
    /// OpenAI masks: fully transparent where the model may edit, opaque elsewhere.
    /// `crop` is the visible part of the source (from `ImageTools.fillCrop`); strokes are mapped into it.
    static func png(strokes: [MaskStroke], size: PixelSize,
                    crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> Data? {
        guard !strokes.isEmpty,
              let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = CGFloat(size.width), h = CGFloat(size.height)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setBlendMode(.clear)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for s in strokes {
            ctx.setLineWidth(s.radius / crop.width * 2 * w)
            let pts = s.points.map { p -> CGPoint in
                let x = (p.x - crop.minX) / crop.width
                let y = (p.y - crop.minY) / crop.height
                return CGPoint(x: x * w, y: (1 - y) * h)
            }
            guard let first = pts.first else { continue }
            ctx.beginPath()
            ctx.move(to: first)
            if pts.count == 1 { ctx.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) }
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        }
        guard let cg = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
