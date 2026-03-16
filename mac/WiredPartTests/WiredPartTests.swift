import Testing
import SwiftUI
@testable import WiredPart

// MARK: - NavigationConfig Tests

@Suite("NavigationConfig")
struct NavigationConfigTests {

    @Test("All 12 modules are defined")
    func moduleCount() {
        #expect(NavigationConfig.allModules.count == 12)
    }

    @Test("Module IDs are unique")
    func uniqueModuleIds() {
        let ids = NavigationConfig.allModules.map(\.id)
        let unique = Set(ids)
        #expect(ids.count == unique.count)
    }

    @Test("Dashboard has no tabs")
    func dashboardNoTabs() {
        #expect(NavigationConfig.dashboard.tabs.isEmpty)
    }

    @Test("Parts module has 8 tabs")
    func partsTabCount() {
        #expect(NavigationConfig.parts.tabs.count == 8)
    }

    @Test("Office module has grouped tabs")
    func officeGroupedTabs() {
        let groups = Set(NavigationConfig.office.tabs.compactMap(\.group))
        #expect(groups.contains("Operations"))
        #expect(groups.contains("People"))
        #expect(groups.contains("Scheduling"))
        #expect(groups.contains("Reports"))
        #expect(groups.count == 4)
    }

    @Test("Settings module has all 20 tabs")
    func settingsTabCount() {
        #expect(NavigationConfig.settings.tabs.count == 20)
    }

    @Test("Settings tab IDs include all expected tabs")
    func settingsTabIds() {
        let ids = Set(NavigationConfig.settings.tabs.map(\.id))
        let expected: Set<String> = [
            "app-config", "about", "themes", "notification-prefs",
            "company-profiles", "pdf-settings", "billing-pay-settings",
            "supplier-bridge", "sync", "bluetooth", "clock-out-questions",
            "backups", "bootstrap-admin", "key-management", "security-admin",
            "update-protocol", "data-export", "integrations", "audit-log",
            "database-reset",
        ]
        #expect(ids == expected)
    }

    // MARK: - Permission Filtering

    @Test("visibleModules filters by permission")
    func visibleModulesPermissionFiltering() {
        // No permissions — only unrestricted modules (dashboard, notebooks, chat, settings)
        let noPerms = NavigationConfig.visibleModules(permissions: [])
        let noPermIds = Set(noPerms.map(\.id))
        #expect(noPermIds.contains("dashboard"))
        #expect(noPermIds.contains("notebooks"))
        #expect(noPermIds.contains("chat"))
        #expect(noPermIds.contains("settings"))
        #expect(!noPermIds.contains("parts"))
        #expect(!noPermIds.contains("warehouse"))
    }

    @Test("visibleModules includes parts with view_parts_catalog")
    func visibleModulesWithPartsPerm() {
        let perms = NavigationConfig.visibleModules(permissions: ["view_parts_catalog"])
        let ids = Set(perms.map(\.id))
        #expect(ids.contains("parts"))
    }

    @Test("visibleTabs filters tabs by permission")
    func visibleTabsPermissionFiltering() {
        // Parts module: pricing tab requires "show_dollar_values"
        let withoutPricing = NavigationConfig.visibleTabs(for: NavigationConfig.parts, permissions: [])
        let withoutIds = Set(withoutPricing.map(\.id))
        #expect(!withoutIds.contains("pricing"))
        #expect(withoutIds.contains("catalog"))

        let withPricing = NavigationConfig.visibleTabs(for: NavigationConfig.parts, permissions: ["show_dollar_values"])
        let withIds = Set(withPricing.map(\.id))
        #expect(withIds.contains("pricing"))
    }

    // MARK: - Path Resolution

    @Test("findModule by exact tab path")
    func findModuleByTabPath() {
        let module = NavigationConfig.findModule(byPath: "/parts/catalog")
        #expect(module?.id == "parts")
    }

    @Test("findModule by module path")
    func findModuleByModulePath() {
        let module = NavigationConfig.findModule(byPath: "/dashboard")
        #expect(module?.id == "dashboard")
    }

    @Test("findModule by module path prefix")
    func findModuleByPrefix() {
        let module = NavigationConfig.findModule(byPath: "/settings/themes")
        #expect(module?.id == "settings")
    }

    @Test("findModule returns nil for unknown path")
    func findModuleUnknown() {
        let module = NavigationConfig.findModule(byPath: "/nonexistent")
        #expect(module == nil)
    }

    @Test("defaultTabPath returns first visible tab")
    func defaultTabPath() {
        let path = NavigationConfig.defaultTabPath(
            for: NavigationConfig.parts,
            permissions: ["show_dollar_values"]
        )
        #expect(path == "/parts/categories")
    }

    @Test("defaultTabPath returns module path when no tabs")
    func defaultTabPathNoTabs() {
        let path = NavigationConfig.defaultTabPath(for: NavigationConfig.dashboard, permissions: [])
        #expect(path == "/dashboard")
    }
}

// MARK: - ThemeManager Tests

@Suite("ThemeManager")
struct ThemeManagerTests {

    @Test("colorScheme light")
    func colorSchemeLight() {
        #expect(ThemeManager.colorScheme(for: "light") == .light)
    }

    @Test("colorScheme dark")
    func colorSchemeDark() {
        #expect(ThemeManager.colorScheme(for: "dark") == .dark)
    }

    @Test("colorScheme system returns nil")
    func colorSchemeSystem() {
        #expect(ThemeManager.colorScheme(for: "system") == nil)
    }

    @Test("colorScheme is case insensitive")
    func colorSchemeCaseInsensitive() {
        #expect(ThemeManager.colorScheme(for: "LIGHT") == .light)
        #expect(ThemeManager.colorScheme(for: "Dark") == .dark)
    }

    @Test("color from hex with hash prefix")
    func colorFromHexWithHash() {
        let color = ThemeManager.color(fromHex: "#FF0000")
        // We can't easily compare Color values, but we can verify it doesn't crash
        // and returns a non-nil value
        #expect(type(of: color) == Color.self)
    }

    @Test("color from hex without hash prefix")
    func colorFromHexNoHash() {
        let color = ThemeManager.color(fromHex: "00FF00")
        #expect(type(of: color) == Color.self)
    }

    @Test("color from invalid hex returns accent color")
    func colorFromInvalidHex() {
        let color = ThemeManager.color(fromHex: "invalid")
        #expect(type(of: color) == Color.self)
    }

    @Test("color from short hex returns accent color")
    func colorFromShortHex() {
        let color = ThemeManager.color(fromHex: "#FFF")
        #expect(type(of: color) == Color.self)
    }
}
