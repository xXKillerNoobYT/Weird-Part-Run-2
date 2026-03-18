import SwiftUI
import Combine
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
    @State private var showAIAssistant = false

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
                        .environmentObject(tabPrefs)
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
        .overlay(alignment: .bottomTrailing) {
            Button {
                showAIAssistant = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .dsMinTapTarget()
            .padding(.trailing, DS.Space.lg)
            .padding(.bottom, 90) // Above the tab bar
        }
        .sheet(isPresented: $showAIAssistant) {
            IOSAIAssistantPanel()
                .environmentObject(appCore)
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
        .onReceive(NotificationCenter.default.publisher(for: .navigateToModule)) { notification in
            if let moduleId = notification.userInfo?["moduleId"] as? String {
                selectedModuleId = moduleId
            }
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
                        .environmentObject(tabPrefs)
                }
            }
        }
    }
}

// MARK: - Module Host View

/// Hosts a single module's content with either a horizontal capsule sub-tab bar
/// or a left sidebar, based on the user's navigation style preference.
///
/// **Important:** This view does NOT own a NavigationStack. The parent
/// (primary tab or More tab) provides the navigation context. This avoids
/// the double-nested NavigationStack bug that breaks "More" tab navigation.
struct ModuleHostView: View {
    let module: AppModule
    @Binding var showLogoutConfirm: Bool
    @EnvironmentObject private var appCore: AppCore
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @State private var selectedTabId: String = ""
    @State private var showUserMenu = false

    /// Tabs visible to the current user after permission filtering.
    private var visibleTabsList: [AppTab] {
        visibleTabs(for: module, permissions: appCore.permissions)
    }

    /// Whether to use sidebar layout — requires sidebar preference AND more than 1 tab.
    private var useSidebar: Bool {
        tabPrefs.navigationStyle == .sidebar && visibleTabsList.count > 1
    }

    var body: some View {
        Group {
            if useSidebar {
                sidebarLayout
            } else {
                topTabsLayout
            }
        }
        .navigationTitle(module.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showUserMenu = true
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        }
        .sheet(isPresented: $showUserMenu) {
            UserMenuSheet(showLogoutConfirm: $showLogoutConfirm)
                .environmentObject(appCore)
                .environmentObject(tabPrefs)
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

    // MARK: - Top Tabs Layout (existing)

    @ViewBuilder
    private var topTabsLayout: some View {
        VStack(spacing: 0) {
            if visibleTabsList.count > 1 {
                subTabPicker
            }

            IOSContentRouter(path: currentPath)
                .environmentObject(appCore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sidebar Layout

    @ViewBuilder
    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            // Left sidebar with tab list
            ScrollView {
                VStack(spacing: DS.Space.xxs) {
                    ForEach(visibleTabsList) { tab in
                        Button {
                            dsAnimate(DS.Anim.fast) {
                                selectedTabId = tab.id
                            }
                        } label: {
                            sidebarRow(tab: tab, selected: tab.id == selectedTabId)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, DS.Space.sm)
                .padding(.horizontal, DS.Space.xs)
            }
            .frame(width: sidebarWidth)
            .background(DS.Background.page)

            Divider()

            // Content area
            IOSContentRouter(path: currentPath)
                .environmentObject(appCore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Sidebar width adapts to device — wider on iPad/Mac.
    private var sidebarWidth: CGFloat {
        DeviceContext.isLargeScreen ? 220 : 180
    }

    @ViewBuilder
    private func sidebarRow(tab: AppTab, selected: Bool) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: tab.icon)
                .font(.body)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 24)

            Text(tab.label)
                .dsStyle(.bodyText)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? .primary : .secondary)

            Spacer()
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Top Tabs Capsule Picker

    @ViewBuilder
    private var subTabPicker: some View {
        let chipH: CGFloat = 14
        let isSelected: (AppTab) -> Bool = { $0.id == selectedTabId }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.sm) {
                ForEach(visibleTabsList) { tab in
                    Button {
                        dsAnimate(DS.Anim.fast) {
                            selectedTabId = tab.id
                        }
                    } label: {
                        subTabChip(tab: tab, selected: isSelected(tab), chipH: chipH)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)
        }
        .background(DS.Background.page)
    }

    @ViewBuilder
    private func subTabChip(tab: AppTab, selected: Bool, chipH: CGFloat) -> some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: tab.icon)
                .font(.caption)
            Text(tab.label)
                .dsStyle(.detail)
                .fontWeight(selected ? .semibold : .regular)
        }
        .padding(.horizontal, chipH)
        .padding(.vertical, DS.Space.sm)
        .background(
            Capsule()
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? .white : .primary)
    }
}
