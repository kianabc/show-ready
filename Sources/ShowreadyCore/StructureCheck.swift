import Foundation

/// Compares the structure (edge layout) of a source photo and an AI edit, so the
/// app can catch a model that redrew the building instead of relighting it.
/// Pure math on luminance buffers; the app layer renders images to gray.
///
/// Method: Sobel edge magnitude on both images, a small blur for resampling
/// tolerance, then Pearson correlation. Correlation ignores overall gain, so an
/// honest relight (twilight, golden hour) scores high while moved stairs,
/// changed windows or a reshaped porch pull the score down.
public enum StructureCheck {
    /// Long edge images are downscaled to before comparing.
    public static let workingEdge = 160

    /// Scores below this are flagged for review in the UI and the edit log.
    /// Calibrated on a real repaint (score ~0.1) vs relight-style edits (~0.9).
    public static let warnBelow = 0.5

    /// 0 (different structure) to 1 (same structure).
    /// `a` and `b` are row-major luminance buffers in 0...1, same dimensions.
    public static func score(_ a: [Float], _ b: [Float], width: Int, height: Int) -> Double {
        guard width > 4, height > 4, a.count == width * height, b.count == a.count else { return 0 }
        let ea = boxBlur(sobelMagnitude(a, width, height), width, height)
        let eb = boxBlur(sobelMagnitude(b, width, height), width, height)
        return max(0, min(1, pearson(ea, eb)))
    }

    static func sobelMagnitude(_ g: [Float], _ w: Int, _ h: Int) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let gx = (g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1])
                       - (g[i - w - 1] + 2 * g[i - 1] + g[i + w - 1])
                let gy = (g[i + w - 1] + 2 * g[i + w] + g[i + w + 1])
                       - (g[i - w - 1] + 2 * g[i - w] + g[i - w + 1])
                out[i] = (gx * gx + gy * gy).squareRoot()
            }
        }
        return out
    }

    /// 3x3 box blur; gives the comparison tolerance for ~1px resampling shifts.
    static func boxBlur(_ g: [Float], _ w: Int, _ h: Int) -> [Float] {
        var out = g
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                var s: Float = 0
                for dy in -1...1 { for dx in -1...1 { s += g[i + dy * w + dx] } }
                out[i] = s / 9
            }
        }
        return out
    }

    static func pearson(_ a: [Float], _ b: [Float]) -> Double {
        let n = Double(a.count)
        guard n > 1 else { return 0 }
        var sa = 0.0, sb = 0.0
        for v in a { sa += Double(v) }
        for v in b { sb += Double(v) }
        let ma = sa / n, mb = sb / n
        var cov = 0.0, va = 0.0, vb = 0.0
        for i in a.indices {
            let da = Double(a[i]) - ma, db = Double(b[i]) - mb
            cov += da * db; va += da * da; vb += db * db
        }
        if va == 0 || vb == 0 { return va == vb ? 1 : 0 }
        return cov / (va * vb).squareRoot()
    }
}
