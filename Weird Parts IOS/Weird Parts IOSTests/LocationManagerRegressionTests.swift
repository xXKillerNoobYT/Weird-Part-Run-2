import XCTest

/// Regression coverage for WEI-3917.
///
/// The Dashboard > Clock route must not block on a simulator GPS request before
/// rendering Clock In / Out. Location is only used to sort jobs by distance, so
/// a missing/stalled fix should resolve quickly and let clock data load.
final class LocationManagerRegressionTests: XCTestCase {
    func testCurrentLocationRequestHasBoundedTimeout() throws {
        let source = try Self.readAppSource("LocationManager.swift")

        XCTAssertTrue(
            source.contains("func getCurrentLocation(timeout: TimeInterval = 2.0) async -> CLLocation?"),
            "LocationManager.getCurrentLocation must keep a short default timeout so Clock page navigation cannot hang on simulator GPS."
        )
        XCTAssertTrue(source.contains("timeoutTask = Task"))
        XCTAssertTrue(source.contains("Task.sleep(nanoseconds:"))
        XCTAssertTrue(source.contains("finishLocationRequest(nil)"))
        XCTAssertTrue(source.contains("manager.requestLocation()"))
    }

    func testLocationCallbacksUseSingleFinishPath() throws {
        let source = try Self.readAppSource("LocationManager.swift")

        XCTAssertTrue(source.contains("private func finishLocationRequest(_ location: CLLocation?)"))
        XCTAssertTrue(source.contains("timeoutTask?.cancel()"))
        XCTAssertTrue(source.contains("continuation?.resume(returning: location)"))
        XCTAssertTrue(source.contains("finishLocationRequest(location)"))
        XCTAssertTrue(source.contains("finishLocationRequest(nil)"))
        XCTAssertFalse(
            source.contains("continuation?.resume(returning: nil)\n            continuation = nil"),
            "Timeout, success, and failure paths should share finishLocationRequest so the timeout is cancelled on all completions."
        )
    }

    private static func readAppSource(_ fileName: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("App")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
