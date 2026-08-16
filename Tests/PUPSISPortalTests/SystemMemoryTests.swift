import XCTest
@testable import PUPSISPortal

/// `shouldWarn` is the only part of `SystemMemory` worth unit testing — the
/// Mach calls behind `availableBytes()` are real-machine-only, the same
/// boundary the rest of this app draws around AppKit/IO glue.
final class SystemMemoryTests: XCTestCase {
    private let gigabyte: Int64 = 1_073_741_824

    func testAComfortablySmallModelDoesNotWarn() {
        XCTAssertFalse(SystemMemory.shouldWarn(modelBytes: gigabyte, availableBytes: UInt64(gigabyte * 16)))
    }

    func testAModelOverTheThresholdWarns() {
        // 10GB model, 12GB available — well past the default 0.6 threshold.
        XCTAssertTrue(SystemMemory.shouldWarn(modelBytes: gigabyte * 10, availableBytes: UInt64(gigabyte * 12)))
    }

    func testAModelExactlyAtTheThresholdDoesNotWarn() {
        // Strictly-greater comparison: exactly at the threshold is still fine.
        XCTAssertFalse(SystemMemory.shouldWarn(modelBytes: gigabyte * 6, availableBytes: UInt64(gigabyte * 10), threshold: 0.6))
    }

    func testACustomThresholdIsHonored() {
        let modelBytes = gigabyte * 5
        let availableBytes = UInt64(gigabyte * 10)
        XCTAssertFalse(SystemMemory.shouldWarn(modelBytes: modelBytes, availableBytes: availableBytes, threshold: 0.6))
        XCTAssertTrue(SystemMemory.shouldWarn(modelBytes: modelBytes, availableBytes: availableBytes, threshold: 0.4))
    }

    func testZeroOrNegativeInputsNeverWarn() {
        XCTAssertFalse(SystemMemory.shouldWarn(modelBytes: 0, availableBytes: UInt64(gigabyte)))
        XCTAssertFalse(SystemMemory.shouldWarn(modelBytes: gigabyte, availableBytes: 0))
        XCTAssertFalse(SystemMemory.shouldWarn(modelBytes: -1, availableBytes: UInt64(gigabyte)))
    }
}
