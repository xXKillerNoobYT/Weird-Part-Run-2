import SwiftUI

/// Root authenticated view with a three-column split layout:
/// - Sidebar: module list
/// - Content: tab bar + routed feature view
struct MainView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var selectedModuleId: String = "dashboard"
    @State private var selectedPath: String = "/dashboard"

    private var selectedModule: NavModule? {
        NavigationConfig.allModules.first { $0.id == selectedModuleId }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedModuleId: $selectedModuleId,
                onModuleSelected: { module in
                    let defaultPath = NavigationConfig.defaultTabPath(
                        for: module,
                        permissions: appCore.permissions
                    )
                    selectedPath = defaultPath.isEmpty ? module.path : defaultPath
                }
            )
        } detail: {
            VStack(spacing: 0) {
                if let module = selectedModule, !module.tabs.isEmpty {
                    TabBarView(
                        module: module,
                        selectedPath: $selectedPath
                    )
                }
                ContentRouter(path: selectedPath)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
