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
    @EnvironmentObject private var badgeManager: BadgeCountManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedModuleId: String = "dashboard"
    @State private var showLogoutConfirm = false
    @State private var showAIAssistant = false
    @State private var aiDisplayMode: AIDisplayMode = .sheet
    @State private var activeRootSheet: RootSheet?
    @State private var moduleNavigationRequests: [String: ModuleNavigationRequest] = [:]
    @State private var moreNavigationPath: [String] = []
    @State private var pendingAIHelpRequest: [AnyHashable: Any]?

    enum RootSheet: Identifiable {
        case conflictReview
        case aiAssistant

        var id: Self { self }
    }

    // Full sidebar state
    @State private var expandedModuleId: String? = "dashboard"
    @State private var selectedTabPath: String = "/dashboard"

    // Single active-sheet enum for sidebar layout to avoid multiple .sheet conflicts
    enum SidebarSheet: Identifiable {
        case userMenu
        case tabEditor
        case aiAssistant

        var id: Self { self }
    }

    @State private var activeSidebarSheet: SidebarSheet?

    // Tab-view layout still uses separate booleans since sheets are on different NavigationStacks
    @State private var showTabEditor = false
    @State private var showUserMenu = false

    /// Modules visible to the current user (permission-filtered, no settings on mobile).
    private var filteredModules: [AppModule] {
        visibleModules(permissions: appCore.permissions)
            .filter { $0.id != "settings" }
    }

    /// Filtered modules in the user's preferred order.
    private var orderedModules: [AppModule] {
        let modules = tabPrefs.orderedModules(from: filteredModules)
        if isUITestingOpenWarehouse {
            guard let warehouseIndex = modules.firstIndex(where: { $0.id == "warehouse" }) else {
                return modules
            }
            var reordered = modules
            let warehouse = reordered.remove(at: warehouseIndex)
            reordered.insert(warehouse, at: min(3, reordered.count))
            return reordered
        }

        guard isUITestingOpenPartsCategories else { return modules }

        // UI tests for Parts > Categories should validate the feature, not the
        // compact "More" list traversal. In testing only, pin Parts into the
        // primary TabView set so selectedModuleId can open it deterministically.
        guard let partsIndex = modules.firstIndex(where: { $0.id == "parts" }) else {
            return modules
        }
        var reordered = modules
        let parts = reordered.remove(at: partsIndex)
        reordered.insert(parts, at: min(3, reordered.count))
        return reordered
    }

    /// Test-only deep link used by GH#568 UI tests. Requires both flags so a
    /// stray feature flag cannot affect production or manual debug launches.
    private var isUITestingOpenPartsCategories: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingOpenPartsCategories")
    }

    /// Test-only deep link for visual QA reruns that need the warehouse floor
    /// plan page without depending on manual tab traversal.
    private var isUITestingOpenWarehouseLocations: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingWarehouseLocations")
    }

    /// Test-only deep link for screenshot runs that must capture the KPI
    /// dashboard without depending on compact tab traversal.
    private var isUITestingOpenWarehouseDashboard: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingWarehouseDashboard")
    }

    /// Test-only deep link for clock flow UI QA. Requires `-UITesting` so the
    /// flag cannot alter production or manual debug navigation.
    private var isUITestingOpenDashboardClock: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingOpenDashboardClock")
    }

    private var isUITestingOpenWarehouse: Bool {
        isUITestingOpenWarehouseLocations || isUITestingOpenWarehouseDashboard
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
        VStack(spacing: 0) {
            SyncConflictBanner { activeRootSheet = .conflictReview }
                .environmentObject(appCore)

            Group {
                if tabPrefs.navigationStyle == .fullSidebar {
                    fullSidebarLayout
                } else {
                    tabViewLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $activeRootSheet) { sheet in
            switch sheet {
            case .conflictReview:
                SyncConflictReviewPage()
                    .environmentObject(appCore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .aiAssistant:
                IOSAIAssistantPanel(
                    displayMode: $aiDisplayMode,
                    isVisible: $showAIAssistant,
                    pendingHelpRequest: $pendingAIHelpRequest
                )
                    .environmentObject(appCore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Log out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                appCore.logout()
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            NewUserWelcomeView()
                .environmentObject(appCore)
        }
        .overlay {
            ModuleTourView()
        }
        .onAppear {
            tabPrefs.load(userId: appCore.currentUser?.id)
            if isUITestingOpenPartsCategories {
                selectedModuleId = "parts"
                expandedModuleId = "parts"
                selectedTabPath = "/parts/categories"
            } else if isUITestingOpenWarehouseLocations {
                selectedModuleId = "warehouse"
                expandedModuleId = "warehouse"
                selectedTabPath = "/warehouse/locations"
                moduleNavigationRequests["warehouse"] = ModuleNavigationRequest(
                    moduleId: "warehouse",
                    tabId: "warehouse-locations"
                )
            } else if isUITestingOpenWarehouseDashboard {
                selectedModuleId = "warehouse"
                expandedModuleId = "warehouse"
                selectedTabPath = "/warehouse/dashboard"
                moduleNavigationRequests["warehouse"] = ModuleNavigationRequest(
                    moduleId: "warehouse",
                    tabId: "warehouse-dashboard"
                )
            } else if isUITestingOpenDashboardClock {
                selectedModuleId = "dashboard"
                expandedModuleId = "dashboard"
                selectedTabPath = "/dashboard/clock"
                moduleNavigationRequests["dashboard"] = ModuleNavigationRequest(
                    moduleId: "dashboard",
                    tabId: "dashboard-clock"
                )
            }
            badgeManager.refresh()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                badgeManager.refresh()
            }
        }
        .onChange(of: showAIAssistant) { _, isVisible in
            syncAIAssistantPresentation(isVisible: isVisible, displayMode: aiDisplayMode)
        }
        .onChange(of: aiDisplayMode) { _, newMode in
            syncAIAssistantPresentation(isVisible: showAIAssistant, displayMode: newMode)
        }
        .onChange(of: activeRootSheet) { _, newSheet in
            guard tabPrefs.navigationStyle != .fullSidebar,
                  aiDisplayMode == .sheet,
                  showAIAssistant,
                  !isAIAssistantRootSheet(newSheet)
            else { return }

            showAIAssistant = false
        }
        // Safety: this .onReceive closure captures tabPrefs and appCore strongly, but that is fine.
        // IOSMainView is only shown when appCore.currentUser != nil (see WiredPartIOSApp.swift).
        // On logout, currentUser becomes nil and SwiftUI tears down this entire view, which
        // automatically cancels the Combine subscription. No manual deregistration needed.
        .onReceive(NotificationCenter.default.publisher(for: .navigateToModule)) { notification in
            if let moduleId = notification.userInfo?["moduleId"] as? String {
                let requestedTabId = notification.userInfo?["tabId"] as? String
                if tabPrefs.navigationStyle == .fullSidebar {
                    // Navigate within full sidebar
                    expandedModuleId = moduleId
                    if let module = allModulesById[moduleId] {
                        let tabs = visibleTabs(for: module, permissions: appCore.permissions)
                        if let requestedTabId,
                           let requestedTab = tabs.first(where: { $0.id == requestedTabId || $0.path == requestedTabId }) {
                            selectedTabPath = requestedTab.path
                        } else if let firstTab = tabs.first {
                            selectedTabPath = firstTab.path
                        }
                    }
                } else {
                    if let requestedTabId {
                        moduleNavigationRequests[moduleId] = ModuleNavigationRequest(moduleId: moduleId, tabId: requestedTabId)
                    }
                    routeToModuleInTabLayout(moduleId)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .askAIAboutHelp)) { notification in
            pendingAIHelpRequest = notification.userInfo
            presentAssistantForHelpRequest()
        }
    }

    /// Presents the assistant after `PageHelpSheet.onDisappear` confirms Help dismissed.
    /// The mounted assistant consumes the payload after its initial history load.
    private func presentAssistantForHelpRequest() {
        aiDisplayMode = .sheet
        if tabPrefs.navigationStyle == .fullSidebar {
            activeSidebarSheet = .aiAssistant
        } else {
            activeRootSheet = .aiAssistant
        }
        showAIAssistant = true
    }

    private func routeToModuleInTabLayout(_ moduleId: String) {
        if primaryModules.contains(where: { $0.id == moduleId }) {
            selectedModuleId = moduleId
            return
        }

        guard overflowModules.contains(where: { $0.id == moduleId }) else { return }
        moreNavigationPath = [moduleId]
        selectedModuleId = "__more__"
    }

    // MARK: - Tab View Layout (existing)

    @ViewBuilder
    private var tabViewLayout: some View {
        TabView(selection: $selectedModuleId) {
            ForEach(primaryModules) { module in
                NavigationStack {
                    ModuleHostView(
                        module: module,
                        showLogoutConfirm: $showLogoutConfirm,
                        navigationRequest: moduleNavigationRequests[module.id]
                    )
                        .environmentObject(appCore)
                        .environmentObject(tabPrefs)
                }
                .tabItem {
                    Label(module.label, systemImage: module.icon)
                }
                .tag(module.id)
                .badge(badgeManager.badge(for: module.id))
                .accessibilityIdentifier("tab_\(module.id)")
            }

            moreTab
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag("__more__")
                .accessibilityIdentifier("tab_more")
        }
        .overlay(alignment: .bottomTrailing) {
            if !showAIAssistant || aiDisplayMode == .sheet {
                aiFloatingButton(bottomPadding: 90)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showAIAssistant && aiDisplayMode == .overlay {
                IOSAIAssistantPanel(
                    displayMode: $aiDisplayMode,
                    isVisible: $showAIAssistant,
                    pendingHelpRequest: $pendingAIHelpRequest
                )
                    .environmentObject(appCore)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .padding(.bottom, 90)
            }
        }
    }

    // MARK: - Full Sidebar Layout

    @ViewBuilder
    private var fullSidebarLayout: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left sidebar with all modules
                fullSidebarView
                    .frame(width: DeviceContext.isLargeScreen ? 240 : 200)

                Divider()

                // Content area
                IOSContentRouter(path: selectedTabPath)
                    .environmentObject(appCore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        activeSidebarSheet = .userMenu
                    } label: {
                        Image(systemName: "person.circle")
                    }
                    .accessibilityLabel("Account and settings")
                    .accessibilityIdentifier("userMenuButton")
                }
            }
        }
        .sheet(item: $activeSidebarSheet) { sheet in
            switch sheet {
            case .userMenu:
                UserMenuSheet(showLogoutConfirm: $showLogoutConfirm)
                    .environmentObject(appCore)
                    .environmentObject(tabPrefs)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .tabEditor:
                TabBarEditorView(allVisibleModules: filteredModules)
                    .environmentObject(tabPrefs)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .aiAssistant:
                IOSAIAssistantPanel(
                    displayMode: $aiDisplayMode,
                    isVisible: $showAIAssistant,
                    pendingHelpRequest: $pendingAIHelpRequest
                )
                    .environmentObject(appCore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !showAIAssistant || aiDisplayMode == .sheet {
                aiFloatingButton(bottomPadding: DS.Space.xl)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showAIAssistant && aiDisplayMode == .overlay {
                IOSAIAssistantPanel(
                    displayMode: $aiDisplayMode,
                    isVisible: $showAIAssistant,
                    pendingHelpRequest: $pendingAIHelpRequest
                )
                    .environmentObject(appCore)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .padding(.bottom, DS.Space.xl)
            }
        }
        .onChange(of: activeSidebarSheet) { _, newSheet in
            guard tabPrefs.navigationStyle == .fullSidebar,
                  aiDisplayMode == .sheet,
                  showAIAssistant,
                  !isAIAssistantSidebarSheet(newSheet)
            else { return }

            showAIAssistant = false
        }
    }

    private func syncAIAssistantPresentation(isVisible: Bool, displayMode: AIDisplayMode) {
        guard displayMode == .sheet else {
            clearAIAssistantSheetHosts()
            return
        }

        guard isVisible else {
            clearAIAssistantSheetHosts()
            return
        }

        if tabPrefs.navigationStyle == .fullSidebar {
            activeSidebarSheet = .aiAssistant
        } else {
            activeRootSheet = .aiAssistant
        }
    }

    private func clearAIAssistantSheetHosts() {
        if isAIAssistantRootSheet(activeRootSheet) {
            activeRootSheet = nil
        }

        if isAIAssistantSidebarSheet(activeSidebarSheet) {
            activeSidebarSheet = nil
        }
    }

    private func isAIAssistantRootSheet(_ sheet: RootSheet?) -> Bool {
        guard case .aiAssistant = sheet else { return false }
        return true
    }

    private func isAIAssistantSidebarSheet(_ sheet: SidebarSheet?) -> Bool {
        guard case .aiAssistant = sheet else { return false }
        return true
    }

    // MARK: - Full Sidebar View

    @ViewBuilder
    private var fullSidebarView: some View {
        VStack(spacing: 0) {
            fullSidebarHeader
            Divider()
            fullSidebarModuleList
            Divider()
            fullSidebarActions
        }
        .background(DS.Background.page)
    }

    @ViewBuilder
    private var fullSidebarHeader: some View {
        HStack {
            Text("Wired Part")
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
    }

    @ViewBuilder
    private var fullSidebarModuleList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(orderedModules) { module in
                    fullSidebarModuleRow(module)
                }
            }
            .padding(.vertical, DS.Space.xs)
            .padding(.horizontal, DS.Space.xs)
        }
    }

    @ViewBuilder
    private func fullSidebarModuleRow(_ module: AppModule) -> some View {
        let moduleTabs = visibleTabs(for: module, permissions: appCore.permissions)
        let isExpanded = expandedModuleId == module.id

        VStack(spacing: 0) {
            fullSidebarModuleHeader(module: module, isExpanded: isExpanded, tabCount: moduleTabs.count)

            if isExpanded && moduleTabs.count > 1 {
                fullSidebarSubTabs(moduleTabs)
            }
        }
    }

    @ViewBuilder
    private func fullSidebarModuleHeader(module: AppModule, isExpanded: Bool, tabCount: Int) -> some View {
        let moduleTabs = visibleTabs(for: module, permissions: appCore.permissions)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedModuleId = nil
                } else {
                    expandedModuleId = module.id
                    if let firstTab = moduleTabs.first {
                        let currentlyInModule = moduleTabs.contains(where: { $0.path == selectedTabPath })
                        if !currentlyInModule {
                            selectedTabPath = firstTab.path
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: module.icon)
                    .font(.body)
                    .foregroundStyle(isExpanded ? Color.accentColor : .secondary)
                    .frame(width: 24)

                Text(module.label)
                    .font(.subheadline)
                    .fontWeight(isExpanded ? .semibold : .regular)
                    .foregroundStyle(isExpanded ? .primary : .secondary)

                Spacer()

                // Badge count indicator for sidebar
                let moduleBadge = badgeManager.badge(for: module.id)
                if moduleBadge > 0 {
                    Text("\(moduleBadge)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(badgeManager.shouldUseRedTint ? Color.red : Color.green)
                        )
                }

                if tabCount > 1 {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isExpanded ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("tab_\(module.id)")
        .accessibilityLabel(module.label)
        .accessibilityHint(tabCount > 1 ? "Show \(module.label) sections" : "Open \(module.label)")
    }

    @ViewBuilder
    private func fullSidebarSubTabs(_ tabs: [AppTab]) -> some View {
        VStack(spacing: 0) {
            ForEach(tabs) { tab in
                fullSidebarTabRow(tab)
            }
        }
        .padding(.bottom, DS.Space.xxs)
    }

    @ViewBuilder
    private func fullSidebarTabRow(_ tab: AppTab) -> some View {
        let isSelected = tab.path == selectedTabPath

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTabPath = tab.path
            }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: tab.icon)
                    .font(.caption)
                    .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                Text(tab.label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.leading, DS.Space.md + 24 + DS.Space.sm)
            .padding(.trailing, DS.Space.md)
            .padding(.vertical, DS.Space.xs + 2)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("subtab_\(tab.id)")
        .accessibilityLabel(tab.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
        .accessibilityHint("Open the \(tab.label) section")
    }

    @ViewBuilder
    private var fullSidebarActions: some View {
        VStack(spacing: DS.Space.xxs) {
            Button {
                activeSidebarSheet = .tabEditor
            } label: {
                sidebarActionRow(icon: "square.grid.2x2", label: "Edit Tabs")
            }
            .buttonStyle(.plain)

            Button {
                activeSidebarSheet = .userMenu
            } label: {
                sidebarActionRow(icon: "person.circle", label: "Account")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.xs)
    }

    @ViewBuilder
    private func sidebarActionRow(icon: String, label: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .frame(width: 24)
            Text(label)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
    }

    // MARK: - AI Floating Button

    @ViewBuilder
    private func aiFloatingButton(bottomPadding: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                if tabPrefs.navigationStyle == .fullSidebar && aiDisplayMode == .sheet {
                    activeSidebarSheet = .aiAssistant
                } else if aiDisplayMode == .sheet {
                    activeRootSheet = .aiAssistant
                }
                showAIAssistant = true
            }
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
        .accessibilityLabel("AI Assistant")
        .accessibilityIdentifier("aiAssistantButton")
        .padding(.trailing, DS.Space.lg)
        .padding(.bottom, bottomPadding)
    }

    // MARK: - More Tab

    @ViewBuilder
    private var moreTab: some View {
        NavigationStack(path: $moreNavigationPath) {
            List {
                // Overflow modules
                if !overflowModules.isEmpty {
                    Section("Modules") {
                        ForEach(overflowModules) { module in
                            NavigationLink(value: module.id) {
                                Label(module.label, systemImage: module.icon)
                            }
                            .badge(badgeManager.badge(for: module.id))
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
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(for: String.self) { moduleId in
                if let module = allModulesById[moduleId] {
                    ModuleHostView(
                        module: module,
                        showLogoutConfirm: $showLogoutConfirm,
                        navigationRequest: moduleNavigationRequests[module.id]
                    )
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
struct ModuleNavigationRequest: Equatable {
    let moduleId: String
    let tabId: String
    private let token = UUID()
}

struct ModuleHostView: View {
    let module: AppModule
    @Binding var showLogoutConfirm: Bool
    let navigationRequest: ModuleNavigationRequest?
    @EnvironmentObject private var appCore: AppCore
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @State private var selectedTabId: String = ""
    @State private var showUserMenu = false

    /// Scroll-edge state for the horizontal sub-tab strip. Drives the edge
    /// fade scrims that signal more tabs exist beyond the screen edge (#1099).
    private struct SubTabScrollEdges: Equatable {
        var canScrollLeading = false
        var canScrollTrailing = false
    }
    @State private var subTabScrollEdges = SubTabScrollEdges()

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
                .accessibilityLabel("Account and settings")
                .accessibilityIdentifier("userMenuButton")
            }
        }
        .sheet(isPresented: $showUserMenu) {
            UserMenuSheet(showLogoutConfirm: $showLogoutConfirm)
                .environmentObject(appCore)
                .environmentObject(tabPrefs)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            applyNavigationRequest(navigationRequest)
            if isUITestingOpenPartsCategories, module.id == "parts" {
                selectedTabId = "parts-categories"
            } else if isUITestingOpenDashboardClock, module.id == "dashboard" {
                selectedTabId = "dashboard-clock"
            } else if isUITestingOpenWarehouseDashboard, module.id == "warehouse" {
                selectedTabId = "warehouse-dashboard"
            } else if isUITestingOpenWarehouseLocations, module.id == "warehouse" {
                selectedTabId = "warehouse-locations"
            } else if selectedTabId.isEmpty, let first = visibleTabsList.first {
                selectedTabId = first.id
            }
        }
        .onChange(of: navigationRequest) { _, request in
            applyNavigationRequest(request)
        }
    }

    /// Test-only deep link used by GH#568 UI tests. This is intentionally
    /// duplicated inside ModuleHostView so sub-tab selection stays local to the
    /// module host and remains inert unless the UI-test harness opts in.
    private var isUITestingOpenPartsCategories: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingOpenPartsCategories")
    }

    private var isUITestingOpenWarehouseLocations: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingWarehouseLocations")
    }

    private var isUITestingOpenWarehouseDashboard: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingWarehouseDashboard")
    }

    private var isUITestingOpenDashboardClock: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingOpenDashboardClock")
    }

    private var currentPath: String {
        visibleTabsList.first { $0.id == selectedTabId }?.path
            ?? visibleTabsList.first?.path
            ?? "/dashboard"
    }

    private func applyNavigationRequest(_ request: ModuleNavigationRequest?) {
        guard request?.moduleId == module.id, let tabId = request?.tabId else { return }
        if let requested = visibleTabsList.first(where: { $0.id == tabId || $0.path == tabId }) {
            selectedTabId = requested.id
        }
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
                        let isSelected = tab.id == selectedTabId

                        Button {
                            dsAnimate(DS.Anim.fast) {
                                selectedTabId = tab.id
                            }
                        } label: {
                            sidebarRow(tab: tab, selected: isSelected)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("subtab_\(tab.id)")
                        .accessibilityLabel(tab.label)
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
                        .accessibilityHint("Open the \(tab.label) warehouse section")
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
        .frame(minHeight: 44)
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

        ScrollViewReader { proxy in
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
                        // Glass buttons inside a horizontally scrolling, narrow iPhone
                        // sub-tab strip can report invalid accessibility activation
                        // points to XCTest. Keep the chip styling in `subTabChip`, but
                        // give automation a plain, explicitly-sized hit region.
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("subtab_\(tab.id)")
                        .accessibilityLabel(tab.label)
                        .accessibilityValue(isSelected(tab) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(isSelected(tab) ? .isSelected : [])
                        .accessibilityRemoveTraits(isSelected(tab) ? [] : .isSelected)
                        .id(tab.id)
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
            }
            .onAppear {
                guard !selectedTabId.isEmpty else { return }
                proxy.scrollTo(selectedTabId, anchor: .center)
            }
            .onChange(of: selectedTabId) { _, selectedId in
                guard !selectedId.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(selectedId, anchor: .center)
                }
            }
            .onScrollGeometryChange(for: SubTabScrollEdges.self) { geometry in
                let maxOffsetX = geometry.contentSize.width - geometry.containerSize.width
                // 1pt tolerance avoids fade flicker from sub-pixel scroll offsets.
                return SubTabScrollEdges(
                    canScrollLeading: maxOffsetX > 1 && geometry.contentOffset.x > 1,
                    canScrollTrailing: maxOffsetX > 1 && geometry.contentOffset.x < maxOffsetX - 1
                )
            } action: { _, edges in
                subTabScrollEdges = edges
            }
            // Edge fades: without an affordance, a partially clipped trailing
            // chip (e.g. after "Daily Report" on compact iPhones) reads as
            // broken layout instead of scrollable content (#1099).
            .overlay(alignment: .leading) {
                if subTabScrollEdges.canScrollLeading {
                    subTabEdgeFade(.leading)
                }
            }
            .overlay(alignment: .trailing) {
                if subTabScrollEdges.canScrollTrailing {
                    subTabEdgeFade(.trailing)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: subTabScrollEdges)
        }
        .background(DS.Background.page)
    }

    /// Gradient scrim shown at a sub-tab strip edge while more chips remain
    /// scrolled off-screen in that direction. Purely decorative — taps pass
    /// through and it is hidden from accessibility.
    @ViewBuilder
    private func subTabEdgeFade(_ edge: HorizontalEdge) -> some View {
        LinearGradient(
            colors: [DS.Background.page, DS.Background.page.opacity(0)],
            startPoint: edge == .leading ? .leading : .trailing,
            endPoint: edge == .leading ? .trailing : .leading
        )
        .frame(width: DS.Space.xxl)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        .frame(minWidth: 44, minHeight: 44)
        .background(
            Capsule()
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? .white : .primary)
    }
}
