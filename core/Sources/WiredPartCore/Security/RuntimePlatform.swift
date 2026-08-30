import Foundation

/// Runtime platform facts shared by Keychain callers.
///
/// `targetEnvironment(macCatalyst)` alone misses the iPad binary running on an
/// Apple Silicon Mac, which uses the same Mac Keychain behavior.
public enum RuntimePlatform {
    public static var isRunningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        return isRunningOnMac(isCatalyst: true, isiOSAppOnMac: false)
        #elseif canImport(UIKit)
        return isRunningOnMac(
            isCatalyst: false,
            isiOSAppOnMac: ProcessInfo.processInfo.isiOSAppOnMac
        )
        #else
        return false
        #endif
    }

    /// Kept explicit so every Mac form has deterministic regression coverage.
    public static func isRunningOnMac(isCatalyst: Bool, isiOSAppOnMac: Bool) -> Bool {
        isCatalyst || isiOSAppOnMac
    }
}