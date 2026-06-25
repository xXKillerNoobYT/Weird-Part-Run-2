import CoreLocation
import Combine
import SwiftUI
import os.log

/// Lightweight wrapper around CLLocationManager for single location fixes.
///
/// Used by the clock in/out flow to capture GPS coordinates. Requests
/// "when in use" authorization on first access.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?
    nonisolated let logger = Logger(subsystem: "com.wiredpart.ios", category: "LocationManager")

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var permissionDenied = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest

        // UI-test simulator runs can block the app's main thread while CoreLocation
        // synchronously queries locationd for the current authorization status.
        // The Clock page can still be tested without a real GPS fix, so avoid that
        // XPC round-trip entirely under the explicit UI-testing launch flag.
        guard !isUITesting else {
            authorizationStatus = .authorizedWhenInUse
            permissionDenied = false
            return
        }

        authorizationStatus = manager.authorizationStatus
        permissionDenied = (authorizationStatus == .denied || authorizationStatus == .restricted)
    }

    /// Request "when in use" location permission.
    ///
    /// Checks current authorization status first to avoid redundant prompts.
    /// If previously denied or restricted, sets `permissionDenied` so the UI
    /// can show an "Open Settings" prompt instead of silently failing.
    func requestPermission() {
        guard !isUITesting else {
            authorizationStatus = .authorizedWhenInUse
            permissionDenied = false
            return
        }

        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            permissionDenied = true
        case .authorizedWhenInUse, .authorizedAlways:
            permissionDenied = false
        @unknown default:
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Get a single location fix. Returns nil if location services
    /// are unavailable, denied, or do not produce a fix before `timeout`.
    ///
    /// Simulator location requests can otherwise remain outstanding long enough
    /// for XCTest to treat navigation into the Clock page as a hung event loop.
    /// Clock data should still load without GPS; GPS only improves job sorting.
    func getCurrentLocation(timeout: TimeInterval = 2.0) async -> CLLocation? {
        guard !isUITesting else { return nil }

        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { cont in
            // Resolve any stale in-flight request before starting a new one so
            // overlapping refreshes cannot leak or resume the wrong continuation.
            finishLocationRequest(nil)
            self.continuation = cont
            timeoutTask = Task { [weak self] in
                let nanoseconds = UInt64(max(timeout, 0.1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.logger.warning("[LocationManager] Location request timed out")
                    self?.finishLocationRequest(nil)
                }
            }
            manager.requestLocation()
        }
    }

    private func finishLocationRequest(_ location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: location)
        continuation = nil
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            finishLocationRequest(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("[LocationManager] Error: \(error.localizedDescription)")
        Task { @MainActor in
            finishLocationRequest(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.permissionDenied = (status == .denied || status == .restricted)
        }
    }
}
