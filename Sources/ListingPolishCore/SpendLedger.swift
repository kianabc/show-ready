import Foundation

/// One finished API call, for the spend history and the edit log export.
public struct SpendEntry: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var photoName: String
    public var model: String
    public var quality: ImageQuality
    public var estimated: Double
    public var actual: Double?
    public var edits: [String]

    public init(date: Date = Date(), photoName: String, model: String, quality: ImageQuality,
                estimated: Double, actual: Double?, edits: [String]) {
        self.date = date; self.photoName = photoName; self.model = model; self.quality = quality
        self.estimated = estimated; self.actual = actual; self.edits = edits
    }

    public var cost: Double { actual ?? estimated }
}

public struct SpendLedger: Codable, Hashable, Sendable {
    public var entries: [SpendEntry] = []
    public init() {}

    public var total: Double { entries.reduce(0) { $0 + $1.cost } }

    public func total(inMonthOf date: Date, calendar: Calendar = .current) -> Double {
        entries.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .reduce(0) { $0 + $1.cost }
    }

    public var averagePerPhoto: Double { entries.isEmpty ? 0 : total / Double(entries.count) }
}
