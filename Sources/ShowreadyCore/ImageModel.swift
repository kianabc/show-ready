import Foundation

/// Quality levels accepted by the OpenAI Images API.
public enum ImageQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high, xhigh, max

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .low: return "Low (draft)"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra high"
        case .max: return "Max"
        }
    }
}

/// How a model accepts output sizes.
public enum SizeMode: String, Codable, Sendable {
    /// Only 1024x1024, 1536x1024 and 1024x1536.
    case fixedThree
    /// Any WIDTHxHEIGHT with edges in multiples of 16, within pixel and aspect limits.
    case custom
}

/// One OpenAI image model and the prices used for cost estimates.
/// Prices are USD per 1 million tokens and are editable in Settings,
/// because OpenAI changes them.
public struct ImageModel: Codable, Identifiable, Hashable, Sendable {
    public var id: String               // exact API model ID
    public var displayName: String
    public var textInputPerM: Double
    public var imageInputPerM: Double
    public var imageOutputPerM: Double
    public var sizeMode: SizeMode
    public var qualities: [ImageQuality]
    /// Send `input_fidelity=high`. Only some older models accept this parameter.
    public var sendsInputFidelity: Bool
    public var notes: String

    public init(id: String, displayName: String, textInputPerM: Double, imageInputPerM: Double,
                imageOutputPerM: Double, sizeMode: SizeMode, qualities: [ImageQuality],
                sendsInputFidelity: Bool = false, notes: String = "") {
        self.id = id
        self.displayName = displayName
        self.textInputPerM = textInputPerM
        self.imageInputPerM = imageInputPerM
        self.imageOutputPerM = imageOutputPerM
        self.sizeMode = sizeMode
        self.qualities = qualities
        self.sendsInputFidelity = sendsInputFidelity
        self.notes = notes
    }

    public var maxLongEdge: Int { sizeMode == .custom ? 3840 : 1536 }
}

public enum ModelCatalog {
    /// Standard-tier prices from OpenAI's pricing page, checked 2026-11-05.
    public static let defaults: [ImageModel] = {
        let new: [ImageQuality] = [.low, .medium, .high, .xhigh, .max]
        let classic: [ImageQuality] = [.low, .medium, .high]
        return [
            ImageModel(id: "gpt-image-2", displayName: "GPT Image 2",
                       textInputPerM: 5, imageInputPerM: 8, imageOutputPerM: 30,
                       sizeMode: .custom, qualities: classic,
                       notes: "Well documented costs. Good default for listings."),
            ImageModel(id: "gpt-image-2.6-sunburst", displayName: "GPT Image 2.6 Sunburst",
                       textInputPerM: 5, imageInputPerM: 8, imageOutputPerM: 30,
                       sizeMode: .custom, qualities: new,
                       notes: "Newest flagship. Supports up to 4K output."),
            ImageModel(id: "gpt-image-2.6-flare", displayName: "GPT Image 2.6 Flare",
                       textInputPerM: 5, imageInputPerM: 8, imageOutputPerM: 30,
                       sizeMode: .custom, qualities: new,
                       notes: "Newest flagship. Supports markup-guided edits."),
            ImageModel(id: "gpt-image-2.5-sunburst", displayName: "GPT Image 2.5 Sunburst",
                       textInputPerM: 5, imageInputPerM: 8, imageOutputPerM: 30,
                       sizeMode: .custom, qualities: new),
            ImageModel(id: "gpt-image-2.5-flare", displayName: "GPT Image 2.5 Flare",
                       textInputPerM: 5, imageInputPerM: 8, imageOutputPerM: 30,
                       sizeMode: .custom, qualities: new),
            ImageModel(id: "gpt-image-1.5", displayName: "GPT Image 1.5 (legacy)",
                       textInputPerM: 5, imageInputPerM: 8, imageOutputPerM: 32,
                       sizeMode: .fixedThree, qualities: classic, sendsInputFidelity: true,
                       notes: "Max 1536x1024. Reportedly retiring."),
            ImageModel(id: "gpt-image-1-mini", displayName: "GPT Image 1 Mini (cheap)",
                       textInputPerM: 2, imageInputPerM: 2.5, imageOutputPerM: 8,
                       sizeMode: .fixedThree, qualities: classic,
                       notes: "Cheapest. Max 1536x1024. Weaker at fine detail. Reportedly retiring."),
        ]
    }()
}
