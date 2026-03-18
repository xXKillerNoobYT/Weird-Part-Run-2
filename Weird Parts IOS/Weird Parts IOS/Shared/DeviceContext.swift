import SwiftUI

/// Device form factor detection for adaptive layouts.
///
/// Usage:
///   @Environment(\.deviceForm) private var deviceForm
///
///   if deviceForm == .iPad {
///       // show sidebar layout
///   }
///
/// Or use the static helpers directly:
///   if DeviceContext.isIPad { ... }
///   if DeviceContext.isiPhone { ... }

enum DeviceForm: String, Sendable {
    case iPhone
    case iPad
    case mac
}

struct DeviceContext {
    /// Current device form factor.
    static var current: DeviceForm {
        #if os(macOS)
        return .mac
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPad
        } else {
            return .iPhone
        }
        #else
        return .iPhone
        #endif
    }

    static var isiPhone: Bool { current == .iPhone }
    static var isIPad: Bool { current == .iPad }
    static var isMac: Bool { current == .mac }

    /// True if the device has a large screen (iPad or Mac).
    static var isLargeScreen: Bool { current != .iPhone }
}

// MARK: - Environment Key

private struct DeviceFormKey: EnvironmentKey {
    static let defaultValue: DeviceForm = DeviceContext.current
}

extension EnvironmentValues {
    var deviceForm: DeviceForm {
        get { self[DeviceFormKey.self] }
        set { self[DeviceFormKey.self] = newValue }
    }
}
