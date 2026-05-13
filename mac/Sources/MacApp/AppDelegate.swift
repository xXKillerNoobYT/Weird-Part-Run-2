import Cocoa

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var loadingViewController: LoadingViewController?
    private var bootstrapCoordinator: BootstrapCoordinator?
    private var hasHandedOffToMainUI = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSRect(x: 0, y: 0, width: 640, height: 420)
        let window = NSWindow(
            contentRect: size,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Weird Parts"

        let bootstrapTimeoutSeconds = 8
        let loadingViewController = LoadingViewController(timeoutSeconds: bootstrapTimeoutSeconds)
        loadingViewController.onRetry = { [weak self] in
            self?.bootstrapCoordinator?.retry()
        }
        window.contentViewController = loadingViewController
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.loadingViewController = loadingViewController

        let bootstrapDelaySeconds = ProcessInfo.processInfo.environment["WEIRD_PARTS_BOOTSTRAP_DELAY_SECONDS"].flatMap(Double.init) ?? 2
        let coordinator = BootstrapCoordinator(timeout: TimeInterval(bootstrapTimeoutSeconds)) {
            try await Task.sleep(for: .seconds(bootstrapDelaySeconds))
        }

        coordinator.onStateChange = { [weak self] state in
            switch state {
            case .ready:
                self?.handoffToMainUI()
            default:
                self?.loadingViewController?.render(state: state)
            }
        }

        self.bootstrapCoordinator = coordinator
        coordinator.start()
    }

    private func handoffToMainUI() {
        guard !hasHandedOffToMainUI else { return }
        hasHandedOffToMainUI = true
        loadingViewController?.render(state: .ready)
        loadingViewController?.onRetry = nil
        loadingViewController = nil
        bootstrapCoordinator?.onStateChange = nil
        bootstrapCoordinator = nil
        showAppShellPlaceholder()
    }

    private func showAppShellPlaceholder() {
        let shellViewController = NSViewController()
        let shellView = NSView()
        shellView.wantsLayer = true
        shellView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Weird Parts")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Bootstrap completed. App shell is active.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        shellView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: shellView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: shellView.centerYAnchor)
        ])

        shellViewController.view = shellView
        window?.contentViewController = shellViewController
    }
}
