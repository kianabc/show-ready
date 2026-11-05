import XCTest
@testable import ShowreadyCore

final class StagingTests: XCTestCase {
    func testStagingIsMaterialAndPrompted() {
        var o = EditOptions.defaults(for: .interior)
        XCTAssertEqual(o.stagingStyle, .none)
        o.staging = .scandinavian
        XCTAssertTrue(o.isMaterialAlteration)
        XCTAssertTrue(o.summary.contains("virtually staged (scandinavian)"))
        let prompt = PromptBuilder.prompt(for: o)
        XCTAssertTrue(prompt.contains("Virtually stage"))
        XCTAssertTrue(prompt.contains("scandinavian"))
        // The add-only lockdown that keeps staging from redrawing the room.
        XCTAssertTrue(prompt.contains("strictly additive"))
        XCTAssertTrue(prompt.contains("Never block a door"))
        XCTAssertTrue(prompt.contains("Do not move, remove or replace"))
    }

    /// Staged results are judged against a lower structure threshold than
    /// relights (furniture adds edges), but it must still sit far enough
    /// above the calibrated repaint score (~0.1) to catch a redrawn room.
    func testStagedStructureThresholdCatchesRedraws() {
        XCTAssertLessThan(StructureCheck.warnBelowStaged, StructureCheck.warnBelow)
        XCTAssertGreaterThan(StructureCheck.warnBelowStaged, 0.2)
    }

    func testStagingAbsentFromExteriorAndUnstagedPrompts() {
        XCTAssertFalse(PromptBuilder.prompt(for: .defaults(for: .interior)).contains("Virtually stage"))
        XCTAssertFalse(PromptBuilder.prompt(for: .defaults(for: .exterior)).contains("Virtually stage"))
    }

    /// Options saved by builds that predate `staging` must still decode —
    /// the library and saved presets are on disk in that shape. A new
    /// non-optional field here would silently wipe the user's library.
    func testOptionsJSONWithoutStagingKeyStillDecodes() throws {
        var o = EditOptions.defaults(for: .interior)
        o.staging = .modern
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(o)) as! [String: Any]
        dict.removeValue(forKey: "staging")
        let decoded = try JSONDecoder().decode(
            EditOptions.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(decoded.stagingStyle, .none)
        XCTAssertEqual(decoded.kind, .interior)
    }
}
