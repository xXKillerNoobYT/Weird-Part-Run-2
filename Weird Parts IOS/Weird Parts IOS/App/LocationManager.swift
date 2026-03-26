import CoreLocation
import Combine
import SwiftUI

/// Lightweight wrapper around CLLocationManager for single location fixes.
///
/// Used by the clock in/out flow to capture GPS coordinates. Requests
/// "when in use" authorization on first access.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var permissionDenied = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
        permissionDenied = (authorizationStatus == .denied || authorizationStatus == .restricted)
    }

    /// Request "when in use" location permission.
    ///
    /// Checks current authorization status first to avoid redundant prompts.
    /// If previously denied or restricted, sets `permissionDenied` so the UI
    /// can show an "Open Settings" prompt instead of silently failing.
    func requestPermission() {
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
    /// are unavailable or denied.
    func getCurrentLocation() async -> CLLocation? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("[LocationManager] Error: \(error.localizedDescription)")
            continuation?.resume(returning: nil)
            continuation = nil
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
