import SwiftUI
import WiredPartCore

/// Primary navigation shell for iOS.
///
/// Uses a TabView with the first 4 visible modules as dedicated tabs
/// plus a "More" tab that lists remaining modules. Each primary tab
/// gets its own NavigationStack; the "More" tab has a single NavigationStack
/// that pushes ModuleHostView when a module is selected.
struct IOSMainView: View {
    @EnvironmentObject private var appCore: AppCore
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @State private var selectedModuleId: String = "dashboard"
    @State private var showLogoutConfirm = false
    @State private var showTabEditor = false

    /// Modules visible to the current user (permission-filtered, no settings on mobile).
    private var filteredModules: [AppModule] {
        visibleModules(permissions: appCore.permissions)
            .filter { $0.id != "settings" }
    }

    /// Filtered modules in the user's preferred order.
    private var orderedModules: [AppModule] {
        tabPrefs.orderedModules(from: filteredModules)
    }

    /// First 4 ordered modules shown as dedicated bottom tabs.
    private var primaryModules: [AppModule] {
        Array(orderedModules.prefix(4))
    }

    /// Remaining ordered modules shown in the "More" tab.
    private var overflowModules: [AppModule] {
        Array(orderedModules.dropFirst(4))
    }

    var body: some View {
        TabView(selection: $selectedModuleId) {
            // Primary tabs — each gets its own NavigationStack
            ForEach(primaryModules) { module in
                NavigationStack {
                    ModuleHostView(module: module, showLogoutConfirm: $showLogoutConfirm)
                        .environmentObject(appCore)
                }
                .tabItem {
                    Label(module.label, systemImage: module.icon)
                }
                .tag(module.id)
            }

            // "More" tab — single NavigationStack, pushes modules
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
        .onAppear {
            tabPrefs.load(userId: appCore.currentUser?.id)
        }
    }

    // MARK: - More Tab

    @ViewBuilder
    private var moreTab: some View {
        NavigationStack {
            List {
                // Overflow modules
                if !overflowModules.isEmpty {
                    Section("Modules") {
                        ForEach(overflowModules) { module in
                            NavigationLink(value: module.id) {
                                Label(module.label, systemImage: module.icon)
                            }
                        }
                    }
                }

                // Edit & Logout
                Section {
                    Button {
                        showTabEditor = true
                    } label: {
                        Label("Edit Tabs", systemImage: "square.grid.2x2")
                    }

                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showTabEditor) {
                TabBarEditorView(allVisibleModules: filteredModules)
                    .environmentObject(tabPrefs)
            }
            .navigationDestination(for: String.self) { moduleId in
                if let module = allModulesById[moduleId] {
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
///
/// **Important:** This view does NOT own a NavigationStack. The parent
/// (primary tab or More tab) provides the navigation context. This avoids
/// the double-nested NavigationStack bug that breaks "More" tab navigation.
struct ModuleHostView: View {
    let module: AppModule
    @Binding var showLogoutConfirm: Bool
    @EnvironmentObject private var appCore: AppCore
    @State private var selectedTabId: String = ""

    /// Tabs visible to the current user after permission filtering.
    private var visibleTabsList: [AppTab] {
        visibleTabs(for: module, permissions: appCore.permissions)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab capsule picker (only if >1 visible tab)
            if visibleTabsList.count > 1 {
                subTabPicker
            }

            // Content
            IOSContentRouter(path: currentPath)
                .environmentObject(appCore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(module.label)
        .navigationBarTitleDisplayMode(.inline)
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
            if selectedTabId.isEmpty, let first = visibleTabsList.first {
                selectedTabId = first.id
            }
        }
    }

    private var currentPath: String {
        visibleTabsList.first { $0.id == selectedTabId }?.path
            ?? visibleTabsList.first?.path
            ?? "/dashboard"
    }

    @ViewBuilder
    private var subTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabsList) { tab in
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
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}
