import AppKit

@MainActor
final class LoadingViewController: NSViewController {
    struct DiagnosticsAppInfo {
        let version: String
        let build: String
        let bundleIdentifier: String
        let macOSVersion: String
        let locale: String

        static func from(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo, locale: Locale = .current) -> Self {
            let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
            return Self(
                version: appVersion,
                build: build,
                bundleIdentifier: bundleIdentifier,
                macOSVersion: processInfo.operatingSystemVersionString,
                locale: locale.identifier
            )
        }
    }

    struct DiagnosticsPayload: Encodable {
        let schemaVersion: String
        let source: String
        let action: String
        let timestamp: String
        let incidentID: String
        let elapsedSeconds: Int
        let timeoutSeconds: Int
        let failure: FailureContext
        let app: AppContext

        struct FailureContext: Encodable {
            let title: String
            let details: String
            let technicalDetails: String
            let errorType: String
            let errorCode: String
            let errorMessage: String
        }

        struct AppContext: Encodable {
            let version: String
            let build: String
            let bundleIdentifier: String
            let macOSVersion: String
            let locale: String
        }
    }

    var onRetry: (() -> Void)?

    private let timeoutSeconds: Int
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "Loading Weird Parts…")
    private let detailLabel = NSTextField(labelWithString: "Starting core services.")
    private let metaLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let copyDiagnosticsButton = NSButton(title: "Copy Diagnostics", target: nil, action: nil)
    private var copiedResetTask: Task<Void, Never>?
    private var currentFailure: BootstrapCoordinator.Failure?

    init(timeoutSeconds: Int) {
        self.timeoutSeconds = timeoutSeconds
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        copiedResetTask?.cancel()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 4
        detailLabel.lineBreakMode = .byWordWrapping

        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.maximumNumberOfLines = 2
        metaLabel.lineBreakMode = .byWordWrapping
        metaLabel.isHidden = true

        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryTapped)
        retryButton.keyEquivalent = "\r"

        copyDiagnosticsButton.bezelStyle = .rounded
        copyDiagnosticsButton.target = self
        copyDiagnosticsButton.action = #selector(copyDiagnosticsTapped)

        let stack = NSStackView(views: [spinner, titleLabel, detailLabel, metaLabel, retryButton, copyDiagnosticsButton])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        renderLoading()
    }

    func render(state: BootstrapCoordinator.State) {
        switch state {
        case .loading:
            renderLoading()
        case .ready:
            currentFailure = nil
            titleLabel.stringValue = "Ready"
            detailLabel.stringValue = "Bootstrap completed. Preparing the app shell."
            metaLabel.isHidden = true
            spinner.stopAnimation(nil)
            retryButton.isHidden = true
            copyDiagnosticsButton.isHidden = true
        case .failed(let failure):
            currentFailure = failure
            spinner.stopAnimation(nil)
            titleLabel.stringValue = failure.title
            detailLabel.stringValue = failure.details
            metaLabel.stringValue = "Elapsed: \(Int(failure.elapsed))s (timeout: \(Int(failure.timeout))s)  Incident: \(failure.incidentID)"
            metaLabel.isHidden = false
            retryButton.isHidden = false
            copyDiagnosticsButton.isHidden = false
            copyDiagnosticsButton.title = "Copy Diagnostics"
            copyDiagnosticsButton.isEnabled = true
            view.window?.defaultButtonCell = retryButton.cell as? NSButtonCell
            view.window?.makeFirstResponder(retryButton)
        }
    }

    private func renderLoading() {
        currentFailure = nil
        titleLabel.stringValue = "Loading Weird Parts…"
        detailLabel.stringValue = "Starting core services. We'll show recovery options if this takes more than \(timeoutSeconds)s."
        metaLabel.isHidden = true
        spinner.startAnimation(nil)
        retryButton.isHidden = true
        copyDiagnosticsButton.isHidden = true
        copyDiagnosticsButton.title = "Copy Diagnostics"
        copyDiagnosticsButton.isEnabled = true
    }

    @objc
    private func retryTapped() {
        onRetry?()
    }

    @objc
    private func copyDiagnosticsTapped() {
        guard let failure = currentFailure else { return }
        let text = Self.makeDiagnosticsPayloadString(
            failure: failure,
            appInfo: DiagnosticsAppInfo.from(),
            now: Date()
        )
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(text, forType: .string)
        if copied {
            showCopiedConfirmation()
        }
    }

    private func showCopiedConfirmation() {
        copiedResetTask?.cancel()
        copyDiagnosticsButton.title = "Copied ✓"
        copyDiagnosticsButton.isEnabled = false

        copiedResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            copyDiagnosticsButton.title = "Copy Diagnostics"
            copyDiagnosticsButton.isEnabled = true
        }
    }

    static func makeDiagnosticsPayloadString(
        failure: BootstrapCoordinator.Failure,
        appInfo: DiagnosticsAppInfo,
        now: Date
    ) -> String {
        let payload = DiagnosticsPayload(
            schemaVersion: "1",
            source: "bootstrap-loading-recovery",
            action: "copy_diagnostics",
            timestamp: ISO8601DateFormatter().string(from: now),
            incidentID: failure.incidentID,
            elapsedSeconds: Int(failure.elapsed),
            timeoutSeconds: Int(failure.timeout),
            failure: .init(
                title: failure.title,
                details: failure.details,
                technicalDetails: failure.technicalDetails,
                errorType: failure.errorType,
                errorCode: failure.errorCode,
                errorMessage: failure.errorMessage
            ),
            app: .init(
                version: appInfo.version,
                build: appInfo.build,
                bundleIdentifier: appInfo.bundleIdentifier,
                macOSVersion: appInfo.macOSVersion,
                locale: appInfo.locale
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return "{\"schemaVersion\":\"1\",\"source\":\"bootstrap-loading-recovery\",\"action\":\"copy_diagnostics\",\"incidentID\":\"\(failure.incidentID)\",\"error\":\"encoding_failed\"}"
        }
        return text
    }
}
