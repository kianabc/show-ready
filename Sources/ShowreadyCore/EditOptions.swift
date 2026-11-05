import Foundation

public enum PhotoKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case interior, exterior
    public var id: String { rawValue }
    public var label: String { self == .interior ? "Interior" : "Exterior" }
}

public enum DeclutterLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, light, thorough
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "None"
        case .light: return "Light (small loose items)"
        case .thorough: return "Thorough (all personal items)"
        }
    }
}

public enum SkyStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case keep, cleanBlue, blueWithClouds, goldenHour, sunset
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .keep: return "Keep sky (just clean it up)"
        case .cleanBlue: return "Clear blue"
        case .blueWithClouds: return "Blue with soft clouds"
        case .goldenHour: return "Golden hour"
        case .sunset: return "Sunset"
        }
    }
}

public enum TVScreen: String, Codable, CaseIterable, Identifiable, Sendable {
    case leave, black, scenic
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .leave: return "Leave as is"
        case .black: return "Turn off (black)"
        case .scenic: return "Neutral landscape"
        }
    }
}

/// Everything a user can ask for on one photo.
public struct EditOptions: Codable, Hashable, Sendable {
    public var kind: PhotoKind = .interior

    // Always-on professional finishing (can be switched off).
    public var colorAndExposure = true
    public var lensCorrection = true
    public var straightenVerticals = false
    public var removeHarshShadows = true

    // Interior.
    public var declutter: DeclutterLevel = .light
    public var removePersonalPhotos = true
    public var removeWindowGlare = true
    public var windowPull = true
    public var lightsOn = false
    public var fireInFireplace = false
    public var tvScreen: TVScreen = .leave
    public var removeReflections = true

    // Exterior.
    public var sky: SkyStyle = .keep
    public var twilight = false
    public var greenLawn = false
    public var removeCarsAndBins = true
    public var removeSigns = false

    public var customInstructions = ""

    public init() {}

    public static func defaults(for kind: PhotoKind) -> EditOptions {
        var o = EditOptions()
        o.kind = kind
        if kind == .exterior { o.sky = .blueWithClouds }
        return o
    }

    /// Short human list of what will change, used in the edit log and disclosure export.
    public var summary: [String] {
        var s: [String] = []
        if colorAndExposure { s.append("color/exposure") }
        if lensCorrection { s.append("lens correction") }
        if straightenVerticals { s.append("vertical correction") }
        if removeHarshShadows { s.append("shadow softening") }
        switch kind {
        case .interior:
            if declutter != .none { s.append("declutter (\(declutter.rawValue))") }
            if removePersonalPhotos { s.append("personal items removed") }
            if removeWindowGlare { s.append("window glare removed") }
            if windowPull { s.append("window pull") }
            if lightsOn { s.append("lights on") }
            if fireInFireplace { s.append("virtual fire") }
            if tvScreen != .leave { s.append("TV screen \(tvScreen.rawValue)") }
            if removeReflections { s.append("reflections removed") }
        case .exterior:
            if sky != .keep { s.append("sky replaced (\(sky.rawValue))") }
            if twilight { s.append("virtual twilight") }
            if greenLawn { s.append("lawn enhanced") }
            if removeCarsAndBins { s.append("cars/bins removed") }
            if removeSigns { s.append("signs removed") }
        }
        if !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { s.append("custom") }
        return s
    }

    /// True when the edit adds or removes things a buyer would see in person.
    /// Many MLSs require disclosing these as "digitally altered" or "virtually enhanced".
    public var isMaterialAlteration: Bool {
        switch kind {
        case .interior:
            return fireInFireplace || lightsOn || tvScreen == .scenic || declutter == .thorough
        case .exterior:
            return sky != .keep || twilight || greenLawn
        }
    }
}
