import Foundation

/// Runtime platform predicate shared by Keychain consumers.
///
/// iPad apps distributed to Apple-silicon Macs are not Catalyst binaries, so a
/// compile-time Catalyst test alone incorrectly applies iOS-only Keychain
/// attributes to their Keychain queries.
public enum RuntimeMacEnvironment {
    /// Returns true for both Mac Catalyst and an iOS app running on Mac.
    public static var isRunningOnMac: Bool {
        let isCatalyst: Bool
        #if targetEnvironment(macCatalyst)
        isCatalyst = true
        #else
        isCatalyst = false
        #endif

        let isIOSAppOnMac: Bool
        #if canImport(UIKit)
        isIOSAppOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        #else
        isIOSAppOnMac = false
        #endif

        return isRunningOnMac(isCatalyst: isCatalyst, isIOSAppOnMac: isIOSAppOnMac)
    }

    /// The injectable form preserves regression coverage for the iPad-on-Mac
    /// path on non-Mac test runners.
    public static func isRunningOnMac(isCatalyst: Bool, isIOSAppOnMac: Bool) -> Bool {
        isCatalyst || isIOSAppOnMac
    }
}
