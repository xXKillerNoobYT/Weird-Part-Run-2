import SwiftUI
import WiredPartCore

/// First-run permissions priming screen.
///
/// Requests the four system permissions WiredPart uses — Camera, Location,
/// Bluetooth, and Local Network — with plain-English context, instead of letting
/// raw system prompts ambush the user mid-task later. Every permission is
/// optional (the app degrades gracefully), so **Continue** is always available;
/// this screen just gives the user an informed, one-time chance to grant them.
///
/// Shown on both onboarding paths right after the user chooses "Create New" or
/// "Join Existing". Priming Local Network here matters for the join path: the
/// prompt must be answered before `DevicePairingView` starts Bonjour discovery,
/// or the first discovery attempt silently finds nothing.
struct PermissionsPrimingView<Next: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var locationManager = LocationManager()

    /// The screen to continue to once the user is done here.
    private let next: () -> Next

    init(@ViewBuilder next: @escaping () -> Next) {
        self.next = next
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(spacing: 12) {
                    permissionRow(
                        icon: "camera.fill",
                        title: "Camera",
                        why: "Scan QR codes, barcodes, and documents, and pair devices.",
                        status: permissions.camera
                    ) { Task { await permissions.requestCamera() } }

                    permissionRow(
                        icon: "location.fill",
                        title: "Location",
                        why: "Record where you clock in/out and track mileage on job sites.",
                        status: permissions.location
                    ) { permissions.requestLocation(using: locationManager) }

                    permissionRow(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Local Network",
                        why: "Find the shop computer and other devices on your Wi-Fi to sync.",
                        status: permissions.localNetwork
                    ) { permissions.requestLocalNetwork() }

                    permissionRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Bluetooth",
                        why: "Find nearby devices to add and sync with — even without Wi-Fi.",
                        status: permissions.bluetooth
                    ) { permissions.requestBluetooth() }
                }

                Button {
                    Task { await requestAll() }
                } label: {
                    Text("Allow All")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Text("You can change these later in Settings. WiredPart works without them, but scanning and device sync need their permissions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                next()
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
        .onAppear { permissions.refreshStatuses() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .decorativeIconFont(dynamicTypeSize.isAccessibilitySize ? 40 : 52)
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("A few permissions to get set up")
                .font(.title2).fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
            Text("Grant these now so scanning and device-to-device sync just work. Each is optional.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        why: String,
        status: PermissionsManager.Status,
        request: @escaping () -> Void
    ) -> some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.15)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            statusControl(status, request: request)
        }
        .padding(14)
        .dsCard()
    }

    @ViewBuilder
    private func statusControl(
        _ status: PermissionsManager.Status,
        request: @escaping () -> Void
    ) -> some View {
        switch status {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityLabel("Allowed")
        case .denied:
            Button("Settings") { openSettings() }
                .font(.caption).buttonStyle(.bordered)
                .frame(minHeight: 44)
        case .requested:
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Requested")
        case .notDetermined:
            Button("Allow", action: request)
                .font(.caption).fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
    }

    private func requestAll() async {
        await permissions.requestCamera()
        permissions.requestLocation(using: locationManager)
        permissions.requestLocalNetwork()
        permissions.requestBluetooth()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
