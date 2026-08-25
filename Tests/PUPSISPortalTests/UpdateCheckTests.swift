import XCTest
@testable import PUPSISPortal

/// Mirrors `windows/PUPSISPortal.Core.Tests/UpdateCheckTests.cs` — the two
/// platforms must agree on what "newer" means, so the cases are kept in step.
final class UpdateCheckTests: XCTestCase {

    // MARK: isNewer

    func testNewerPatchIsNewer() {
        XCTAssertTrue(UpdateCheck.isNewer("1.1.3", than: "1.1.2"))
    }

    func testNewerMinorIsNewer() {
        XCTAssertTrue(UpdateCheck.isNewer("1.2.0", than: "1.1.9"))
    }

    func testNewerMajorIsNewer() {
        XCTAssertTrue(UpdateCheck.isNewer("2.0.0", than: "1.9.9"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(UpdateCheck.isNewer("1.1.2", than: "1.1.2"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateCheck.isNewer("1.1.1", than: "1.1.2"))
    }

    func testLeadingVIsIgnored() {
        XCTAssertTrue(UpdateCheck.isNewer("v1.1.3", than: "1.1.2"))
        XCTAssertFalse(UpdateCheck.isNewer("V1.1.2", than: "v1.1.2"))
    }

    /// A three-part tag against the Windows app's four-part `<Version>`: the
    /// missing fourth segment reads as 0, so they compare equal rather than the
    /// shorter one looking older.
    func testMissingSegmentsReadAsZero() {
        XCTAssertFalse(UpdateCheck.isNewer("1.1.2", than: "1.1.2.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.1.2.1", than: "1.1.2"))
    }

    func testTwoPartVersionCompares() {
        XCTAssertTrue(UpdateCheck.isNewer("1.2", than: "1.1.9"))
        XCTAssertFalse(UpdateCheck.isNewer("1.1", than: "1.1.0"))
    }

    /// Fails closed: garbage segments read as 0 instead of throwing, so a
    /// malformed tag can never nag the user.
    func testNonNumericFailsClosed() {
        XCTAssertFalse(UpdateCheck.isNewer("banana", than: "1.1.2"))
        XCTAssertFalse(UpdateCheck.isNewer("1.x.9", than: "1.1.2"))
        XCTAssertFalse(UpdateCheck.isNewer("", than: "1.1.2"))
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertTrue(UpdateCheck.isNewer("  1.1.3  ", than: "1.1.2"))
    }

    // MARK: check(current:)

    private func checker(json: String) -> UpdateCheck {
        UpdateCheck { Data(json.utf8) }
    }

    func testCheckReturnsNewerRelease() async {
        let sut = checker(json: """
        {"tag_name":"v1.2.0","html_url":"https://github.com/cGradying/IntPortal/releases/tag/v1.2.0"}
        """)
        let info = await sut.check(current: "1.1.2")
        XCTAssertEqual(info?.version, "1.2.0")
        XCTAssertEqual(info?.url.absoluteString,
                       "https://github.com/cGradying/IntPortal/releases/tag/v1.2.0")
    }

    func testCheckReturnsNilWhenUpToDate() async {
        let sut = checker(json: """
        {"tag_name":"v1.1.2","html_url":"https://example.com/r"}
        """)
        let info = await sut.check(current: "1.1.2")
        XCTAssertNil(info)
    }

    func testCheckReturnsNilWhenRunningNewerThanReleased() async {
        let sut = checker(json: """
        {"tag_name":"v1.1.2","html_url":"https://example.com/r"}
        """)
        let info = await sut.check(current: "1.2.0")
        XCTAssertNil(info)
    }

    func testCheckSwallowsNetworkFailure() async {
        struct Boom: Error {}
        let sut = UpdateCheck { throw Boom() }
        let info = await sut.check(current: "1.1.2")
        XCTAssertNil(info)
    }

    func testCheckSwallowsMalformedJSON() async {
        let sut = checker(json: "not json at all")
        let info = await sut.check(current: "1.1.2")
        XCTAssertNil(info)
    }

    func testCheckReturnsNilWhenTagMissing() async {
        let sut = checker(json: #"{"html_url":"https://example.com/r"}"#)
        let info = await sut.check(current: "1.1.2")
        XCTAssertNil(info)
    }

    func testCheckReturnsNilWhenUrlMissing() async {
        let sut = checker(json: #"{"tag_name":"v9.9.9"}"#)
        let info = await sut.check(current: "1.1.2")
        XCTAssertNil(info)
    }
}
