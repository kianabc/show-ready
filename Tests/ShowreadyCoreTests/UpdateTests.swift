import XCTest
@testable import ShowreadyCore

final class UpdateTests: XCTestCase {
    func testSemanticVersionParsing() {
        XCTAssertEqual(SemanticVersion("1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("1.2")?.description, "1.2.0")
        XCTAssertEqual(SemanticVersion("1.2.0-beta.1")?.description, "1.2.0")
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("not-a-version"))
    }

    func testSemanticVersionComparison() {
        XCTAssertLessThan(SemanticVersion("1.2.3")!, SemanticVersion("1.2.4")!)
        XCTAssertLessThan(SemanticVersion("1.2.9")!, SemanticVersion("1.10.0")!)
        XCTAssertLessThan(SemanticVersion("0.9.9")!, SemanticVersion("1.0.0")!)
        XCTAssertEqual(SemanticVersion("1.2.3")!, SemanticVersion("v1.2.3")!)
        XCTAssertFalse(SemanticVersion("1.2.3")! < SemanticVersion("1.2.3")!)
    }

    func testCombinedNotesFlattensHeadingsAndRules() {
        let notes = UpdateChecker.combinedNotes([
            (SemanticVersion("0.2.0")!, "## What's new\n- **Faster.** Everything.\n---\nEnjoy"),
            (SemanticVersion("0.1.1")!, "- Fixed a crash"),
        ])
        XCTAssertTrue(notes.contains("**Rocco Show Ready 0.2.0**"))
        XCTAssertTrue(notes.contains("**Rocco Show Ready 0.1.1**"))
        XCTAssertTrue(notes.contains("**What's new**"))
        XCTAssertFalse(notes.contains("## "))
        XCTAssertFalse(notes.contains("\n---"))
        // Newest first.
        XCTAssertLessThan(notes.range(of: "0.2.0")!.lowerBound, notes.range(of: "0.1.1")!.lowerBound)
    }

    func testTrustedURLs() {
        XCTAssertNotNil(UpdateChecker.trusted(URL(string: "https://github.com/kianabc/show-ready/releases")!))
        XCTAssertNotNil(UpdateChecker.trusted(URL(string: "https://objects.githubusercontent.com/x.dmg")!))
        XCTAssertNil(UpdateChecker.trusted(URL(string: "http://github.com/x")!), "http is not enough")
        XCTAssertNil(UpdateChecker.trusted(URL(string: "https://evil.com/github.com/x")!))
        XCTAssertNil(UpdateChecker.trusted(URL(string: "file:///etc/passwd")!))
        XCTAssertNil(UpdateChecker.trusted(URL(string: "https://github.com.evil.com/x")!))
    }
}
