import Foundation

public struct PixelSize: Codable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public var pixels: Int { width * height }
    public var megapixels: Double { Double(pixels) / 1_048_576 }
    public var aspect: Double { Double(width) / Double(max(height, 1)) }
    public var apiString: String { "\(width)x\(height)" }
    public var description: String { "\(width)×\(height)" }
}

/// Picks a size the API accepts that keeps the source photo's aspect ratio
/// as closely as the model allows. Keeping the aspect ratio matters: a model
/// forced into a different ratio may stretch or re-frame the room.
public enum OutputSizer {
    public static let minPixels = 655_360
    public static let maxPixels = 8_294_400
    public static let maxEdge = 3840

    public static func size(for source: PixelSize, longEdge requested: Int, model: ImageModel) -> PixelSize {
        switch model.sizeMode {
        case .fixedThree:
            let a = source.aspect
            if a > 1.2 { return PixelSize(width: 1536, height: 1024) }
            if a < 1 / 1.2 { return PixelSize(width: 1024, height: 1536) }
            return PixelSize(width: 1024, height: 1024)
        case .custom:
            return customSize(aspect: source.aspect, longEdge: requested)
        }
    }

    static func customSize(aspect rawAspect: Double, longEdge requested: Int) -> PixelSize {
        let aspect = min(max(rawAspect, 1.0 / 3.0), 3.0)
        var long = Double(min(max(requested, 512), maxEdge))
        func make(_ long: Double) -> PixelSize {
            let landscape = aspect >= 1
            let short = landscape ? long / aspect : long * aspect
            let w = landscape ? long : short
            let h = landscape ? short : long
            var s = PixelSize(width: round16(w), height: round16(h))
            // Rounding must never break the 3:1 limit.
            while s.aspect > 3 { s.height += 16 }
            while s.aspect < 1.0 / 3.0 { s.width += 16 }
            return s
        }
        var s = make(long)
        // Shrink if over the pixel budget.
        while s.pixels > maxPixels { long -= 16; s = make(long) }
        // Grow if under the minimum.
        while s.pixels < minPixels && long < Double(maxEdge) { long += 16; s = make(long) }
        return s
    }

    static func round16(_ v: Double) -> Int { max(16, Int((v / 16).rounded()) * 16) }
}
