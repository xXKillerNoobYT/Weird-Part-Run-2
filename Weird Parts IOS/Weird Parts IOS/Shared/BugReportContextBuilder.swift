import Foundation
import UIKit
import WiredPartCore

/// Gathers the live device, version, page, and recent-error context the beta
/// bug reporter attaches to a report, and hands it to `BugReportComposer`.
///
/// Kept in the app layer because it reaches into UIKit / the app bundle;
/// the composition/encoding logic itself lives in `WiredPartCore` and is
/// unit-tested there.
enum BugReportContextBuilder {
    /// Builds a composer context from live app state.
    ///
    /// - Parameters:
    ///   - currentModule: The page/module the user was on, if known.
    ///   - errorLog: Source of recent user-facing errors.
    @MainActor
    static func build(
        currentModule: String?,
        errorLog: BugReportErrorLog = .shared
    ) -> BugReportComposer.Context {
        BugReportComposer.Context(
            deviceModel: deviceModelName(),
            systemVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: appVersion(),
            appBuild: appBuild(),
            coreVersion: WiredPartCore.version,
            currentModule: currentModule,
            recentErrors: errorLog.composerEntries()
        )
    }

    /// Marketing app version, e.g. "1.4.0".
    static func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Build number, e.g. "128". Empty when unavailable.
    static func appBuild() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    /// The hardware model identifier (e.g. "iPhone16,1"), which is far more
    /// useful in a bug report than the user-chosen device name. Falls back to
    /// `UIDevice.current.model` on the simulator, where the identifier is a
    /// generic env value.
    static func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        // Simulators report "x86_64" / "arm64"; prefer the human model there.
        if trimmed.isEmpty || trimmed == "x86_64" || trimmed == "arm64" {
            return UIDevice.current.model
        }
        return trimmed
    }
}
