import Testing
@testable import WiredPartIOS

@Suite("Navigation Config Tests")
struct NavigationConfigTests {

    @Test("Module count matches expected")
    func testModuleCount() {
        #expect(appModules.count == 12)
    }

    @Test("Find module by ID")
    func testFindModule() {
        let dashboard = findModule("dashboard")
        #expect(dashboard != nil)
        #expect(dashboard?.label == "Dashboard")
        #expect(dashboard?.icon == "square.grid.2x2.fill")

        let settings = findModule("settings")
        #expect(settings != nil)
        #expect(settings?.tabs.count == 20)

        let nonexistent = findModule("nonexistent")
        #expect(nonexistent == nil)
    }

    @Test("Visible modules excludes settings")
    func testVisibleModules() {
        let visible = visibleModules
        #expect(!visible.contains { $0.id == "settings" })
        #expect(visible.count == 11)
        #expect(visible.first?.id == "dashboard")
    }
}
