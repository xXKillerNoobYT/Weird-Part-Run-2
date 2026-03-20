import Foundation
import CoreLocation

@MainActor
final class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var didExitJobRegion = false
    @Published var exitLocation: CLLocationCoordinate2D?
    @Published var exitTime: Date?
    @Published var currentJobId: Int64?
    @Published var currentJobName: String?

    private let locationManager = CLLocationManager()
    private var monitoredRegion: CLCircularRegion?

    static let jobRadiusMeters: Double = 1609.34 // 1 mile

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Start monitoring a 1-mile region around the given job coordinates.
    func startMonitoring(jobId: Int64, jobName: String, latitude: Double, longitude: Double) {
        stopMonitoring()

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: Self.jobRadiusMeters,
            identifier: "job-\(jobId)"
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false

        currentJobId = jobId
        currentJobName = jobName
        monitoredRegion = region
        didExitJobRegion = false
        exitLocation = nil
        exitTime = nil

        locationManager.startMonitoring(for: region)
    }

    /// Stop all region monitoring.
    func stopMonitoring() {
        if let region = monitoredRegion {
            locationManager.stopMonitoring(for: region)
        }
        monitoredRegion = nil
        currentJobId = nil
        currentJobName = nil
        didExitJobRegion = false
        exitLocation = nil
        exitTime = nil
    }

    /// Reset the exit flag after the user handles the alert.
    func acknowledgeExit() {
        didExitJobRegion = false
        exitLocation = nil
        exitTime = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            guard region.identifier == monitoredRegion?.identifier else { return }
            didExitJobRegion = true
            exitTime = Date()
            if let loc = manager.location?.coordinate {
                exitLocation = loc
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("[GeofenceManager] Monitoring failed: \(error.localizedDescription)")
    }
}
