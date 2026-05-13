import XCTest
@testable import WeirdPartsMacApp

@MainActor
final class WeirdPartsMacAppTests: XCTestCase {
    func testTimeoutTransitionEmitsFailedState() async {
        let states = StateRecorder()
        let coordinator = BootstrapCoordinator(timeout: 0.01) {
            try await Task.sleep(for: .seconds(1))
        }

        coordinator.onStateChange = { states.append($0) }
        coordinator.start()

        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(states.containsLoading)
        XCTAssertTrue(states.containsTimeoutFailure)
    }

    func testRetryCanRecoverToReadyState() async {
        let states = StateRecorder()
        let control = BootstrapControl(shouldHang: true)
        let coordinator = BootstrapCoordinator(timeout: 0.02) {
            if await control.currentShouldHang() {
                try await Task.sleep(for: .seconds(1))
            }
        }

        coordinator.onStateChange = { states.append($0) }
        coordinator.start()
        try? await Task.sleep(for: .milliseconds(80))

        await control.setShouldHang(false)
        coordinator.retry()
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(states.loadingCount, 2)
        XCTAssertEqual(states.timeoutFailureCount, 1)
        XCTAssertEqual(states.readyCount, 1)
        XCTAssertEqual(states.normalizedFlow, ["loading", "failed-timeout", "loading", "ready"])
    }

    func testTimeoutFailureIncludesErrorContext() async {
        let states = StateRecorder()
        let coordinator = BootstrapCoordinator(timeout: 0.01) {
            try await Task.sleep(for: .seconds(1))
        }

        coordinator.onStateChange = { states.append($0) }
        coordinator.start()
        try? await Task.sleep(for: .milliseconds(80))

        guard case .failed(let failure) = states.states.last else {
            return XCTFail("Expected final failed state")
        }
        XCTAssertEqual(failure.errorType, "WeirdPartsMacApp.BootstrapCoordinator.TimeoutError")
        XCTAssertEqual(failure.errorMessage, "Bootstrap exceeded 0s timeout")
        XCTAssertEqual(failure.errorCode, "1")
    }

    func testDiagnosticsPayloadIsDeterministicAndParseable() throws {
        let failure = BootstrapCoordinator.Failure(
            incidentID: "INC12345",
            title: "Startup Failed",
            details: "Details",
            technicalDetails: "Tech details",
            errorType: "SampleError",
            errorCode: "42",
            errorMessage: "Boom",
            elapsed: 8.9,
            timeout: 8.0
        )
        let appInfo = LoadingViewController.DiagnosticsAppInfo(
            version: "2.1.0",
            build: "123",
            bundleIdentifier: "com.weirdparts.macapp",
            macOSVersion: "macOS 14.5",
            locale: "en_US"
        )

        let first = LoadingViewController.makeDiagnosticsPayloadString(
            failure: failure,
            appInfo: appInfo,
            now: Date(timeIntervalSince1970: 1_234_567)
        )
        let second = LoadingViewController.makeDiagnosticsPayloadString(
            failure: failure,
            appInfo: appInfo,
            now: Date(timeIntervalSince1970: 1_234_567)
        )
        XCTAssertEqual(first, second)

        let data = try XCTUnwrap(first.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? String, "1")
        XCTAssertEqual(json["source"] as? String, "bootstrap-loading-recovery")
        XCTAssertEqual(json["action"] as? String, "copy_diagnostics")
        XCTAssertEqual(json["incidentID"] as? String, "INC12345")
        XCTAssertEqual(json["elapsedSeconds"] as? Int, 8)
        XCTAssertEqual(json["timeoutSeconds"] as? Int, 8)

        let failureJSON = try XCTUnwrap(json["failure"] as? [String: Any])
        XCTAssertEqual(failureJSON["errorType"] as? String, "SampleError")
        XCTAssertEqual(failureJSON["errorCode"] as? String, "42")
        XCTAssertEqual(failureJSON["errorMessage"] as? String, "Boom")

        let appJSON = try XCTUnwrap(json["app"] as? [String: Any])
        XCTAssertEqual(appJSON["version"] as? String, "2.1.0")
        XCTAssertEqual(appJSON["build"] as? String, "123")
        XCTAssertEqual(appJSON["bundleIdentifier"] as? String, "com.weirdparts.macapp")
    }

    func testDiagnosticsAppInfoFallsBackToUnknownWhenBundleMetadataMissing() {
        let appInfo = LoadingViewController.DiagnosticsAppInfo.from(
            bundle: Bundle(for: Self.self),
            processInfo: ProcessInfo.processInfo,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(appInfo.version, "unknown")
        XCTAssertEqual(appInfo.build, "unknown")
        XCTAssertEqual(appInfo.bundleIdentifier, "ing.paperclip.weirdparts.macapp.tests")
    }
}

private actor BootstrapControl {
    private var shouldHang: Bool

    init(shouldHang: Bool) {
        self.shouldHang = shouldHang
    }

    func currentShouldHang() -> Bool {
        shouldHang
    }

    func setShouldHang(_ newValue: Bool) {
        shouldHang = newValue
    }
}

private final class StateRecorder {
    private(set) var states: [BootstrapCoordinator.State] = []

    func append(_ state: BootstrapCoordinator.State) {
        states.append(state)
    }

    var containsLoading: Bool {
        states.contains {
            if case .loading = $0 { return true }
            return false
        }
    }

    var containsReady: Bool {
        states.contains {
            if case .ready = $0 { return true }
            return false
        }
    }

    var containsTimeoutFailure: Bool {
        states.contains {
            if case .failed(let failure) = $0 {
                return failure.title == "Startup Timed Out"
            }
            return false
        }
    }

    var loadingCount: Int {
        states.filter {
            if case .loading = $0 { return true }
            return false
        }.count
    }

    var readyCount: Int {
        states.filter {
            if case .ready = $0 { return true }
            return false
        }.count
    }

    var timeoutFailureCount: Int {
        states.filter {
            if case .failed(let failure) = $0 {
                return failure.title == "Startup Timed Out"
            }
            return false
        }.count
    }

    var normalizedFlow: [String] {
        states.map {
            switch $0 {
            case .loading:
                return "loading"
            case .ready:
                return "ready"
            case .failed(let failure):
                return failure.title == "Startup Timed Out" ? "failed-timeout" : "failed"
            }
        }
    }
}
