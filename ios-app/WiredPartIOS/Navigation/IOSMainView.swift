import SwiftUI
import WiredPartCore

/// Primary navigation shell for iOS.
///
/// Uses a TabView with the first 4 visible modules as dedicated tabs
/// plus a "More" tab that lists remaining modules. Each tab contains
/// a NavigationStack with a horizontal capsule sub-tab picker for
/// switching between a module's pages.
struct IOSMainView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var selectedModuleId: String = "dashboard"
    @State private var showLogoutConfirm = false

    /// First 4 non-settings modules shown as dedicated tabs.
    private var primaryModules: [AppModule] {
        Array(visibleModules.prefix(4))
    }

    /// Remaining non-settings modules shown in the "More" tab.
    private var overflowModules: [AppModule] {
        Array(visibleModules.dropFirst(4))
    }

    /// The Settings module (always last).
    private var settingsModule: AppModule? {
        findModule("settings")
    }

    var body: some View {
        TabView(selection: $selectedModuleId) {
            // Primary tabs
            ForEach(primaryModules) { module in
                moduleNavigationStack(module)
                    .tabItem {
                        Label(module.label, systemImage: module.icon)
                    }
                    .tag(module.id)
            }

            // "More" tab
            moreTab
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag("__more__")
        }
        .confirmationDialog("Log out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                appCore.logout()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Module Navigation Stack

    /// Builds a NavigationStack for a single module with sub-tab capsule picker.
    @ViewBuilder
    private func moduleNavigationStack(_ module: AppModule) -> some View {
        ModuleHostView(module: module, showLogoutConfirm: $showLogoutConfirm)
            .environmentObject(appCore)
    }

    // MARK: - More Tab

    @ViewBuilder
    private var moreTab: some View {
        NavigationStack {
            List {
                // Overflow modules
                Section("Modules") {
                    ForEach(overflowModules) { module in
                        NavigationLink(value: module.id) {
                            Label(module.label, systemImage: module.icon)
                        }
                    }
                }

                // Settings
                if let settings = settingsModule {
                    Section("Settings") {
                        NavigationLink(value: settings.id) {
                            Label(settings.label, systemImage: settings.icon)
                        }
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("More")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: String.self) { moduleId in
                if let module = findModule(moduleId) {
                    ModuleHostView(module: module, showLogoutConfirm: $showLogoutConfirm)
                        .environmentObject(appCore)
                }
            }
        }
    }
}

// MARK: - Module Host View

/// Hosts a single module's content with a horizontal capsule sub-tab bar
/// and a content area that switches based on the selected tab.
struct ModuleHostView: View {
    let module: AppModule
    @Binding var showLogoutConfirm: Bool
    @EnvironmentObject private var appCore: AppCore
    @State private var selectedTabId: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sub-tab capsule picker (only if >1 tab)
                if module.tabs.count > 1 {
                    subTabPicker
                }

                // Content
                IOSContentRouter(path: currentPath)
                    .environmentObject(appCore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(module.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        if let user = appCore.currentUser {
                            Text(user.displayName)
                        }
                        Divider()
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .onAppear {
                if selectedTabId.isEmpty, let first = module.tabs.first {
                    selectedTabId = first.id
                }
            }
        }
    }

    private var currentPath: String {
        module.tabs.first { $0.id == selectedTabId }?.path
            ?? module.tabs.first?.path
            ?? "/dashboard"
    }

    @ViewBuilder
    private var subTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(module.tabs) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTabId = tab.id
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.label)
                                .font(.subheadline)
                                .fontWeight(selectedTabId == tab.id ? .semibold : .regular)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedTabId == tab.id ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(selectedTabId == tab.id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
    }
}
