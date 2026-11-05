import Foundation

/// Token usage returned by the Images API.
public struct ImageUsage: Codable, Hashable, Sendable {
    public struct InputDetails: Codable, Hashable, Sendable {
        public var text_tokens: Int?
        public var image_tokens: Int?
        public init(text_tokens: Int? = nil, image_tokens: Int? = nil) {
            self.text_tokens = text_tokens; self.image_tokens = image_tokens
        }
    }
    public var input_tokens: Int?
    public var output_tokens: Int?
    public var total_tokens: Int?
    public var input_tokens_details: InputDetails?

    public init(input_tokens: Int? = nil, output_tokens: Int? = nil, total_tokens: Int? = nil,
                input_tokens_details: InputDetails? = nil) {
        self.input_tokens = input_tokens; self.output_tokens = output_tokens
        self.total_tokens = total_tokens; self.input_tokens_details = input_tokens_details
    }

    public var textInputTokens: Int { input_tokens_details?.text_tokens ?? 0 }
    public var imageInputTokens: Int {
        if let i = input_tokens_details?.image_tokens { return i }
        return max(0, (input_tokens ?? 0) - textInputTokens)
    }
    public var outputTokens: Int { output_tokens ?? 0 }
}

public struct CostEstimate: Hashable, Sendable {
    public enum Basis: Hashable, Sendable {
        case published            // from OpenAI's published per-image examples
        case calibrated(Int)      // from N of your own past edits
        case rough                // no published data for this model and quality
    }
    public var textTokens: Int
    public var imageInputTokens: Int
    public var outputTokens: Int
    public var dollars: Double
    public var basis: Basis

    public var basisLabel: String {
        switch basis {
        case .published: return "from OpenAI's published rates"
        case .calibrated(let n): return "from your last \(n) edit\(n == 1 ? "" : "s")"
        case .rough: return "rough guess, will improve after your first edit"
        }
    }
}

/// Averages of real usage, so estimates get accurate after a few edits.
public struct Calibration: Codable, Hashable, Sendable {
    public struct Sample: Codable, Hashable, Sendable {
        public var perMegapixel: Double
        public var count: Int
    }
    public var output: [String: Sample] = [:]   // key: model|quality
    public var input: [String: Sample] = [:]    // key: model

    public init() {}

    static func key(_ model: String, _ q: ImageQuality) -> String { "\(model)|\(q.rawValue)" }

    public mutating func record(model: String, quality: ImageQuality, usage: ImageUsage,
                                outputSize: PixelSize, imageCount: Int, inputSize: PixelSize) {
        if usage.outputTokens > 0, imageCount > 0 {
            let perMP = Double(usage.outputTokens) / Double(imageCount) / outputSize.megapixels
            Calibration.add(&output[Calibration.key(model, quality)], perMP)
        }
        if usage.imageInputTokens > 0 {
            Calibration.add(&input[model], Double(usage.imageInputTokens) / inputSize.megapixels)
        }
    }

    static func add(_ s: inout Sample?, _ v: Double) {
        guard v.isFinite, v > 0 else { return }
        // Running mean over the last ~20 samples.
        if var cur = s {
            let n = Double(min(cur.count, 19))
            cur.perMegapixel = (cur.perMegapixel * n + v) / (n + 1)
            cur.count += 1
            s = cur
        } else {
            s = Sample(perMegapixel: v, count: 1)
        }
    }
}

public enum CostEstimator {
    /// Output tokens per megapixel (1024x1024 = 1 MP), derived from OpenAI's
    /// published per-image costs at 1024x1024.
    static func publishedOutputPerMP(model: String, quality: ImageQuality) -> (Double, CostEstimate.Basis) {
        let gpt2: [ImageQuality: Double] = [.low: 200, .medium: 1767, .high: 7033]
        let tables: [String: [ImageQuality: Double]] = [
            "gpt-image-2": gpt2,
            "gpt-image-1.5": [.low: 272, .medium: 1056, .high: 4160],
            "gpt-image-1-mini": [.low: 625, .medium: 1375, .high: 4500],
        ]
        if let t = tables[model], let v = t[quality] { return (v, .published) }
        // Newer models have no published table. Assume GPT Image 2 behaviour.
        switch quality {
        case .low, .medium, .high: return (gpt2[quality]!, .rough)
        case .xhigh: return (gpt2[.high]! * 1.5, .rough)
        case .max: return (gpt2[.high]! * 2, .rough)
        }
    }

    /// Vision-style tile estimate for an uploaded image: fit in 2048, shortest side to 768,
    /// then 170 tokens per 512px tile plus 85.
    static func tileTokens(for size: PixelSize) -> Int {
        var w = Double(size.width), h = Double(size.height)
        let fit = min(1, 2048 / max(w, h)); w *= fit; h *= fit
        let short = min(1, 768 / min(w, h)); w *= short; h *= short
        let tiles = Int(ceil(w / 512)) * Int(ceil(h / 512))
        return 85 + 170 * tiles
    }

    public static func estimate(model: ImageModel, quality: ImageQuality, inputSize: PixelSize,
                                outputSize: PixelSize, prompt: String, variations: Int = 1,
                                hasMask: Bool = false, calibration: Calibration = Calibration()) -> CostEstimate {
        let n = max(1, variations)
        let textTokens = max(1, prompt.utf8.count / 4)

        var basis: CostEstimate.Basis
        let outPerMP: Double
        if let c = calibration.output[Calibration.key(model.id, quality)] {
            outPerMP = c.perMegapixel; basis = .calibrated(c.count)
        } else {
            (outPerMP, basis) = publishedOutputPerMP(model: model.id, quality: quality)
        }
        let outputTokens = Int((outPerMP * outputSize.megapixels).rounded()) * n

        var inTokens: Int
        if let c = calibration.input[model.id] {
            inTokens = Int((c.perMegapixel * inputSize.megapixels).rounded())
        } else {
            inTokens = tileTokens(for: inputSize)
        }
        if hasMask { inTokens *= 2 }

        let dollars = Double(textTokens) * model.textInputPerM / 1e6
            + Double(inTokens) * model.imageInputPerM / 1e6
            + Double(outputTokens) * model.imageOutputPerM / 1e6
        return CostEstimate(textTokens: textTokens, imageInputTokens: inTokens,
                            outputTokens: outputTokens, dollars: dollars, basis: basis)
    }

    /// Actual cost of a finished call from the usage the API returned.
    public static func actualCost(model: ImageModel, usage: ImageUsage) -> Double {
        Double(usage.textInputTokens) * model.textInputPerM / 1e6
            + Double(usage.imageInputTokens) * model.imageInputPerM / 1e6
            + Double(usage.outputTokens) * model.imageOutputPerM / 1e6
    }
}

public extension Double {
    var dollarString: String {
        if self == 0 { return "$0.00" }
        if self < 0.01 { return String(format: "$%.4f", self) }
        if self < 1 { return String(format: "$%.3f", self) }
        return String(format: "$%.2f", self)
    }
}
