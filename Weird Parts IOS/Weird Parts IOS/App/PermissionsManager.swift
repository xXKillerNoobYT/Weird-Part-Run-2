import AVFoundation
import Combine
import CoreBluetooth
import CoreLocation
import Network
import SwiftUI
import os.log

/// Central coordinator for the system permissions WiredPart depends on.
///
/// The app needs four OS permissions, each requested by a different framework
/// with a different (and inconsistent) API:
///
///  - **Camera** (`AVFoundation`) — QR/barcode/document scanning + device pairing.
///    Clean status query + async request.
///  - **Location** (`CoreLocation`) — clock in/out GPS + mileage. Status query +
///    delegate callback. (The single-fix flow still lives in `LocationManager`;
///    this type only owns the *authorization* concern so onboarding has one place
///    to prime it.)
///  - **Bluetooth** (`CoreBluetooth`) — discovering nearby devices running
///    WiredPart for Multipeer sync/pairing. Status via `CBManager.authorization`;
///    the prompt is triggered simply by *instantiating* a `CBCentralManager`.
///  - **Local Network** (`Network`) — LAN peer discovery/sync over Bonjour. iOS
///    exposes **no** status API; the prompt is triggered by starting a Bonjour
///    browse, and the outcome can only be inferred (best-effort).
///
/// Onboarding uses this to prime permissions at a sensible moment with context,
/// instead of letting raw system prompts ambush the user mid-task. Requesting a
/// permission that is already granted/denied is a safe no-op, so the priming
/// screen can call these freely.
@MainActor
final class PermissionsManager: NSObject, ObservableObject {

    /// Normalized status shared across all four permission types.
    enum Status: Equatable {
        case notDetermined
        case granted
        case denied
        /// Local network only — requested, but iOS won't tell us the outcome.
        case requested

        var isBlocking: Bool { self == .denied }
    }

    @Published private(set) var camera: Status = .notDetermined
    @Published private(set) var location: Status = .notDetermined
    @Published private(set) var bluetooth: Status = .notDetermined
    @Published private(set) var localNetwork: Status = .notDetermined

    nonisolated let logger = Logger(subsystem: "com.wiredpart.ios", category: "PermissionsManager")

    // Bluetooth prompt is triggered by creating a central manager; hold a strong
    // reference so it stays alive long enough to report state back.
    private var btManager: CBCentralManager?
    // Local-network prompt is triggered by an NWBrowser; keep it briefly then cancel.
    private var lanBrowser: NWBrowser?

    /// Mirror `LocationManager`'s guard: UI-test simulator runs can block the main
    /// thread inside the frameworks' synchronous authorization XPC calls. Treat
    /// everything as granted under the explicit UI-testing launch flag.
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    override init() {
        super.init()
        refreshStatuses()
    }

    // MARK: - Status refresh

    /// Re-read the current authorization state for every permission. Call on
    /// `.onAppear` of the priming screen and after returning from Settings.
    func refreshStatuses() {
        guard !isUITesting else {
            camera = .granted; location = .granted; bluetooth = .granted; localNetwork = .granted
            return
        }
        camera = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        location = Self.map(CLLocationManager().authorizationStatus)
        bluetooth = Self.map(CBManager.authorization)
        // localNetwork intentionally not refreshed — no query API; keep last known.
    }

    // MARK: - Camera

    func requestCamera() async {
        guard !isUITesting else { camera = .granted; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            camera = granted ? .granted : .denied
        case .denied, .restricted:
            camera = .denied
        @unknown default:
            camera = .denied
        }
    }

    // MARK: - Location

    /// Trigger the "when in use" location prompt via the shared `LocationManager`
    /// so there is a single CoreLocation delegate in the app.
    func requestLocation(using locationManager: LocationManager) {
        guard !isUITesting else { location = .granted; return }
        locationManager.requestPermission()
        location = Self.map(CLLocationManager().authorizationStatus)
    }

    // MARK: - Bluetooth

    /// Instantiating `CBCentralManager` presents the Bluetooth prompt (when
    /// undetermined). Result arrives asynchronously via the delegate.
    func requestBluetooth() {
        guard !isUITesting else { bluetooth = .granted; return }
        if btManager == nil {
            btManager = CBCentralManager(delegate: self, queue: nil)
        }
        bluetooth = Self.map(CBManager.authorization)
    }

    // MARK: - Local Network

    /// iOS has no local-network authorization query; the only way to raise the
    /// prompt is to actually start Bonjour activity. Start a throwaway browse for
    /// the app's LAN sync service, then tear it down. Outcome is not observable,
    /// so mark `.requested` and rely on real discovery to confirm connectivity.
    func requestLocalNetwork() {
        guard !isUITesting else { localNetwork = .granted; return }
        guard lanBrowser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_wiredpart._tcp", domain: nil),
            using: params
        )
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.logger.error("[Permissions] local-network browse failed: \(String(describing: error))")
            }
        }
        browser.start(queue: .main)
        lanBrowser = browser
        localNetwork = .requested

        // The prompt only needs the browser to run momentarily.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self?.lanBrowser?.cancel()
                self?.lanBrowser = nil
            }
        }
    }

    // MARK: - Mapping helpers

    private static func map(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .notDetermined
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> Status {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .notDetermined
        }
    }

    private static func map(_ status: CBManagerAuthorization) -> Status {
        switch status {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .notDetermined
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PermissionsManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let status = CBManager.authorization
        Task { @MainActor in
            self.bluetooth = Self.map(status)
        }
    }
}
