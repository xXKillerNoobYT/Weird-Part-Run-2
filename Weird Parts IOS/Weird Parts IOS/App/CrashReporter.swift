import Foundation
import UIKit

/// Lightweight in-process crash detector.
///
/// On every app launch, records the session as "active" (unclean) in UserDefaults.
/// If the app exits gracefully (background / willTerminate), the flag is cleared.
/// On the next launch, a still-set flag means the previous session crashed.
///
/// In addition, registers an `NSSetUncaughtExceptionHandler` to capture
/// Objective-C exception payloads, and installs signal handlers for the most
/// common fatal signals (SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE).
///
/// Usage: call `CrashReporter.shared.install()` once in `WiredPartIOSApp.init()`
/// **before** any other initialisation so the previous crash state can be read
/// before the flag is reset for the new session.
final class CrashReporter {

    static let shared = CrashReporter()
    private init() {}

    // MARK: - UserDefaults Keys

    private let sessionActiveKey = "wp_crash_session_active"
    private let lastCrashInfoKey  = "wp_last_crash_info"
    private let lastCrashDateKey  = "wp_last_crash_date"

    // MARK: - Install

    /// Install the crash reporter.  Must be called once from the app's `init()`.
    func install() {
        // 1. Check for a crash from the PREVIOUS session before resetting the flag.
        detectPreviousCrash()

        // 2. Mark session as active (unclean exit assumed until told otherwise).
        UserDefaults.standard.set(true, forKey: sessionActiveKey)
        UserDefaults.standard.synchronize()

        // 3. Objective-C uncaught exception handler.
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.recordCrash(
                reason: exception.reason ?? "Unknown Objective-C exception",
                callStack: exception.callStackSymbols.prefix(20).joined(separator: "\n")
            )
        }

        // 4. Signal handlers for fatal signals (SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE).
        //    Note: only async-signal-safe operations are truly guaranteed in signal context;
        //    UserDefaults writes here are best-effort since the process is already dying.
        [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE].forEach { sig in
            signal(sig) { receivedSignal in
                CrashReporter.shared.recordCrash(
                    reason: "Fatal signal \(receivedSignal) (\(signalName(receivedSignal)))",
                    callStack: Thread.callStackSymbols.prefix(20).joined(separator: "\n")
                )
                // Restore default handler and re-raise so the OS gets the real crash.
                signal(receivedSignal, SIG_DFL)
                raise(receivedSignal)
            }
        }

        // 5. Mark clean exit when the app moves to background or is terminated normally.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(markCleanExit),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(markCleanExit),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - Clean Exit

    @objc private func markCleanExit() {
        UserDefaults.standard.set(false, forKey: sessionActiveKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Previous Crash Detection

    private func detectPreviousCrash() {
        guard UserDefaults.standard.bool(forKey: sessionActiveKey) else { return }

        // Session flag was still set — either the OS killed the app (watchdog, OOM)
        // or a signal/exception was caught but UserDefaults flush failed.
        if UserDefaults.standard.string(forKey: lastCrashInfoKey) == nil {
            let date = ISO8601DateFormatter().string(from: Date())
            let message = """
            The app exited unexpectedly (possible watchdog timeout, memory pressure, \
            or force-quit by the user). No exception details were captured.
            """
            UserDefaults.standard.set(message, forKey: lastCrashInfoKey)
            UserDefaults.standard.set(date, forKey: lastCrashDateKey)
        }
    }

    // MARK: - Recording

    func recordCrash(reason: String, callStack: String) {
        let date = ISO8601DateFormatter().string(from: Date())
        let payload = """
        Date: \(date)
        Reason: \(reason)

        Call Stack:
        \(callStack)
        """
        UserDefaults.standard.set(payload, forKey: lastCrashInfoKey)
        UserDefaults.standard.set(date, forKey: lastCrashDateKey)
        // Clear the session-active flag so the next launch only shows ONE report.
        UserDefaults.standard.set(false, forKey: sessionActiveKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Reading

    /// `true` if there is a crash report from a previous session waiting to be reviewed.
    var hasPendingCrashReport: Bool {
        UserDefaults.standard.string(forKey: lastCrashInfoKey) != nil
    }

    var pendingCrashInfo: String? {
        UserDefaults.standard.string(forKey: lastCrashInfoKey)
    }

    var pendingCrashDate: String? {
        UserDefaults.standard.string(forKey: lastCrashDateKey)
    }

    /// Discards the pending crash report.  Call after the user dismisses or submits it.
    func clearPendingCrashReport() {
        UserDefaults.standard.removeObject(forKey: lastCrashInfoKey)
        UserDefaults.standard.removeObject(forKey: lastCrashDateKey)
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Signal Name Helper

private func signalName(_ sig: Int32) -> String {
    switch sig {
    case SIGABRT: return "SIGABRT"
    case SIGSEGV: return "SIGSEGV"
    case SIGBUS:  return "SIGBUS"
    case SIGILL:  return "SIGILL"
    case SIGFPE:  return "SIGFPE"
    default:      return "SIG\(sig)"
    }
}
