import SwiftUI
import WiredPartCore

struct IOSReportsRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "reports-timesheets": IOSTimesheetsPage()
        case "reports-spending": IOSSpendingPage()
        default: Text("Unknown reports page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
