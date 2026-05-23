import Foundation
import WiredPartCore

/// Pure selection helpers for the JPO detail bulk-hold sheet.
///
/// Keeping this outside the SwiftUI view gives the behavior a focused regression
/// test: selecting multiple rows must carry the selected row snapshot into the
/// hold sheet instead of relying on a second state read during presentation.
enum IOSJPODetailBulkHoldSelection {
    static func selectedHoldItems(
        from lines: [OrdersService.JPOLineRow],
        selectedLineIds: Set<Int64>
    ) -> [OrdersService.JPOLineRow] {
        lines.filter { selectedLineIds.contains($0.id) }
    }

    static func sheetIdentifier(for items: [OrdersService.JPOLineRow]) -> String {
        "bulkHold-" + items.map { String($0.id) }.joined(separator: "-")
    }

    static func processableHoldItems(
        from items: [OrdersService.JPOLineRow],
        failedTransferCancellationLineIds: Set<Int64>
    ) -> [OrdersService.JPOLineRow] {
        items.filter { !failedTransferCancellationLineIds.contains($0.id) }
    }
}
