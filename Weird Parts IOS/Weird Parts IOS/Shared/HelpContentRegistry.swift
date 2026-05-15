import Foundation

/// Central registry of all page help content. Used by the AI assistant to provide
/// contextual help without needing to search through individual page files.
///
/// Each entry mirrors the content from the corresponding page's `PageHelpSheet`.
/// When the user asks the AI "how do I use this page?" or similar questions,
/// the AI system prompt includes the relevant help content for accurate answers.
struct HelpContentRegistry {

    // MARK: - Types

    struct HelpEntry {
        let pageId: String
        let title: String
        let sections: [(String, String)]
    }

    // MARK: - Registry

    /// All registered help entries keyed by page ID (matches `AppTab.id` where possible).
    static let entries: [String: HelpEntry] = {
        var dict: [String: HelpEntry] = [:]
        for entry in allEntries {
            dict[entry.pageId] = entry
        }
        return dict
    }()

    // MARK: - Queries

    /// Get formatted help text for a specific page, ready for inclusion in an AI prompt.
    static func formattedHelp(for pageId: String) -> String? {
        guard let entry = entries[pageId] else { return nil }
        var text = "# \(entry.title)\n\n"
        for (heading, body) in entry.sections {
            text += "## \(heading)\n\(body)\n\n"
        }
        return text
    }

    /// Get help content for a page, or nil if not found.
    static func helpFor(_ pageId: String) -> HelpEntry? {
        entries[pageId]
    }

    /// All available help topic names, sorted alphabetically.
    static var availableTopics: [String] {
        entries.values.map(\.title).sorted()
    }

    /// All page IDs that have help content.
    static var availablePageIds: [String] {
        entries.keys.sorted()
    }

    /// Search help entries by keyword in title or section content.
    /// Returns entries where the keyword appears in the title or any section body.
    static func search(keyword: String) -> [HelpEntry] {
        let lower = keyword.lowercased()
        return allEntries.filter { entry in
            entry.title.lowercased().contains(lower) ||
            entry.sections.contains(where: { $0.0.lowercased().contains(lower) || $0.1.lowercased().contains(lower) })
        }
    }

    /// Build a compact summary of all available help topics for inclusion in AI system prompts.
    /// Returns a string listing each page ID and title.
    static func topicSummaryForAI() -> String {
        var lines: [String] = ["Available Help Topics:"]
        for entry in allEntries.sorted(by: { $0.title < $1.title }) {
            lines.append("- \(entry.pageId): \(entry.title)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Notification-to-PageId Mapping

    /// Maps known page-context notification names to their corresponding page IDs
    /// in this registry. Used to automatically look up help when the AI receives
    /// a page-active notification.
    static let notificationToPageId: [String: String] = [
        "WiredPart.catalogPageActive": "parts-catalog",
        "WiredPart.pricingPageActive": "parts-pricing",
        "WiredPart.suppliersPageActive": "parts-suppliers",
        "WiredPart.companionsPageActive": "parts-companions",
        "WiredPart.forecastingPageActive": "parts-forecasting",
        "WiredPart.dashboardPageActive": "dashboard-home",
        "WiredPart.jobsListPageActive": "jobs-list",
        "WiredPart.clockPageActive": "dashboard-clock",
        "WiredPart.jobDetailPageActive": "jobs-detail",
        "WiredPart.laborPageActive": "jobs-labor",
        "WiredPart.dailyReportsPageActive": "jobs-daily-reports",
        "WiredPart.questionnairePageActive": "jobs-questionnaire",
        "WiredPart.estimationQuestionnairePageActive": "jobs-estimation-questionnaire",
        "WiredPart.estimationReviewPageActive": "jobs-estimation-review",
        "WiredPart.jobReportsPageActive": "jobs-reports",
        "WiredPart.jposPageActive": "orders-jpos",
        "WiredPart.purchaseOrdersPageActive": "orders-pos",
        "WiredPart.poDetailPageActive": "orders-po-detail",
        "WiredPart.receiveShipmentPageActive": "orders-receiving",
        "WiredPart.procurementPageActive": "orders-procurement",
        "WiredPart.returnsPageActive": "orders-returns",
        "WiredPart.jpoCreationPageActive": "orders-jpo-create",
        "WiredPart.jpoDetailPageActive": "orders-jpo-detail",
        "WiredPart.orderStagingPageActive": "orders-staging",
        "WiredPart.partsOrderManagementPageActive": "orders-parts",
        "WiredPart.ordersWishlistPageActive": "orders-wishlist",
        "WiredPart.unifiedOrderPageActive": "orders-unified",
        "WiredPart.warehouseDashboardPageActive": "warehouse-dashboard",
        "WiredPart.inventoryGridPageActive": "warehouse-inventory",
        "WiredPart.warehouseLocationsPageActive": "warehouse-locations",
        "WiredPart.warehouseMovementsPageActive": "warehouse-movements",
        "WiredPart.warehouseReceivingPageActive": "warehouse-receiving",
        "WiredPart.warehouseStagingPageActive": "warehouse-staging",
        "WiredPart.warehouseAuditPageActive": "warehouse-audit",
        "WiredPart.warehouseReturnsPageActive": "warehouse-returns",
        "WiredPart.warehouseToolsPageActive": "warehouse-tools",
        "WiredPart.warehouseNetworkPageActive": "warehouse-network",
        "WiredPart.warehouseSettingsPageActive": "warehouse-settings",
        "WiredPart.warehouseOrganizationAuditPageActive": "warehouse-organization",
        "WiredPart.warehouseLeaderboardPageActive": "warehouse-leaderboard",
        "WiredPart.dispatchPageActive": "scheduling-dispatch",
        "WiredPart.scheduleCalendarPageActive": "scheduling-calendar",
        "WiredPart.employeesPageActive": "people-employees",
        "WiredPart.peopleDashboardPageActive": "people-dashboard",
        "WiredPart.customersPageActive": "people-customers",
        "WiredPart.contactsPageActive": "people-contacts",
        "WiredPart.officeDashboardPageActive": "office-dashboard",
        "WiredPart.officeApprovalsPageActive": "office-approvals",
        "WiredPart.officeSpendingPageActive": "office-spending",
        "WiredPart.reportsLaborPageActive": "reports-labor",
        "WiredPart.reportsSpendingPageActive": "reports-spending",
        "WiredPart.reportsProfitabilityPageActive": "reports-profitability",
        "WiredPart.reportsTimesheetsPageActive": "reports-timesheets",
        "WiredPart.reportsPrebillingPageActive": "reports-prebilling",
        "WiredPart.reportsBookkeeperPageActive": "reports-bookkeeper",
        "WiredPart.reportsDailySummaryPageActive": "reports-daily-summary",
        "WiredPart.vehiclesPageActive": "fleet-vehicles",
        "WiredPart.toolRegistryPageActive": "tools-registry",
        "WiredPart.notebooksListPageActive": "notebooks-all",
    ]

    // MARK: - All Entries (extracted from PageHelpSheet usages)

    /// Complete list of help entries, extracted from the actual PageHelpSheet calls
    /// in each page's source file. Content is verbatim from the page implementations.
    private static let allEntries: [HelpEntry] = [

        // ── DASHBOARD ─────────────────────────────────────────────────────

        HelpEntry(
            pageId: "dashboard-home",
            title: "Dashboard Help",
            sections: [
                ("Overview", "Your daily command center. See clock status, KPI stats, charts, alerts, and quick actions all in one place."),
                ("KPI Cards", "Tap any KPI card to see detailed breakdowns. Cards show part types, total stock, active jobs, pending orders, and low stock warnings."),
                ("Quick Actions", "Use the quick action buttons at the bottom to scan QR codes, clock in/out, view the daily report, move stock, or create new orders."),
            ]
        ),

        // ── JOBS ──────────────────────────────────────────────────────────

        HelpEntry(
            pageId: "jobs-list",
            title: "Jobs Help",
            sections: [
                ("Overview", "View and manage all jobs. Filter by status using the smart cards at the top, or search by name and job number."),
                ("Smart Cards", "Tap a status card to filter. The number shows how many jobs have that status. Payment Hold is only visible to managers."),
                ("Sorting", "Use the sort button in the toolbar to sort by recent activity, name, or start date."),
                ("Creating Jobs", "Tap the + button to create a new job. Requires manage_jobs permission."),
            ]
        ),

        HelpEntry(
            pageId: "jobs-detail",
            title: "Job Detail Help",
            sections: [
                ("Overview", "Full details for this job including status, priority, customer, address, dates, and notes."),
                ("Team & Labor", "See assigned team members and a summary of labor hours logged against this job."),
                ("Actions", "Pull down to refresh. Use the tab view for deeper access to team, labor, parts, and orders."),
            ]
        ),

        HelpEntry(
            pageId: "dashboard-clock",
            title: "Clock In/Out Help",
            sections: [
                ("Clocking In", "Select a job from the GPS-sorted list to clock in. Jobs closest to you appear first. 'Shop / Warehouse' is always pinned at the top."),
                ("Clocking Out", "When clocked in, tap the Clock Out button. You may be prompted to answer clock-out questions before the entry is saved."),
                ("Elapsed Timer", "The large timer shows how long you've been on the current job. It updates every minute automatically."),
                ("Switch Job", "Use the Switch Job button to clock out of the current job and immediately clock into a different one — no need to find the job list again."),
                ("To-Do Tracking", "After clocking in, you can optionally pick a to-do to track what you're working on. Use 'Mark Done' to complete it and pick the next one."),
                ("Today's Hours", "The hours breakdown shows your total time per job with optional per-to-do detail. Warranty entries are marked with a 'W' badge."),
                ("QR Scan", "Use the QR scanner button in the toolbar to scan a job QR code and clock in directly."),
            ]
        ),

        HelpEntry(
            pageId: "jobs-labor",
            title: "Labor Help",
            sections: [
                ("Overview", "Track all labor entries across jobs. Active clock-ins appear at the top with clock-out buttons. Recent history is shown below."),
                ("Clock In", "Tap the play button in the toolbar to start a new clock-in for any employee and job."),
                ("Search", "Use the search bar to filter entries by employee name or job name. Pull down to refresh."),
            ]
        ),

        HelpEntry(
            pageId: "jobs-daily-reports",
            title: "Daily Reports Help",
            sections: [
                ("Overview", "View per-job activity summaries for any date. See worker count, total hours logged, and report status for each job."),
                ("Navigation", "Use the left/right arrows to move between dates. Tap Today to jump back to the current date."),
                ("Data", "Pull down to refresh. Reports are generated automatically based on clock entries and job activity."),
            ]
        ),

        HelpEntry(
            pageId: "jobs-questionnaire",
            title: "Clock-Out Questions Help",
            sections: [
                ("Overview", "Answer required clock-out questions before completing a labor entry. Required items are marked with an asterisk."),
                ("Break Verification", "Record whether breaks were taken. Missed breaks are reported to the office for compliance review."),
                ("Companion Polls", "Optional companion rule votes may appear at the bottom when there are active parts polls."),
            ]
        ),

        HelpEntry(
            pageId: "jobs-estimation-questionnaire",
            title: "Estimation Questionnaire Help",
            sections: [
                ("Purpose", "Answer stage-specific questions to generate a time-and-labor estimate for the job."),
                ("Unknown Answers", "Use the question mark option for details that are not known yet. Unknown fields are excluded from calculation but tracked."),
                ("Calculating", "Calculate Estimate shows days, hours, and confidence based on answered questions and historical jobs."),
            ]
        ),

        HelpEntry(
            pageId: "jobs-estimation-review",
            title: "Estimation Reviews Help",
            sections: [
                ("Purpose", "Compare estimates against actual job progress so future bids improve."),
                ("Weekly Review", "Submit a progress check with notes about surprises, scope changes, or scheduling issues."),
                ("End-of-Job Review", "Capture final actuals and lessons learned when the job closes."),
            ]
        ),

        HelpEntry(
            pageId: "jobs-reports",
            title: "Job Reports Help",
            sections: [
                ("Overview", "Browse daily reports across all jobs. Each report shows the job name, date, status, and reviewer."),
                ("Search", "Use the search bar to filter reports by job name, date, or status."),
                ("Details", "Reports are generated automatically from daily job activity and clock entries."),
            ]
        ),

        // ── PARTS ─────────────────────────────────────────────────────────

        HelpEntry(
            pageId: "parts-catalog",
            title: "Parts Catalog Help",
            sections: [
                ("Overview", "Browse all parts in your inventory. Search by name or code, filter by category, brand, or stock status using the chips."),
                ("Actions", "Tap the + button to add a new part. Use the QR scanner to find parts by code. The printer icon lets you print QR labels."),
                ("Pricing", "Toggle the $ icon to show pricing overlays on each part. Tap a part for full details, long-press for quick edit."),
            ]
        ),

        HelpEntry(
            pageId: "parts-forecasting",
            title: "Forecasting Help",
            sections: [
                ("Overview", "Demand forecasting shows predicted usage for each part based on historical consumption. Color-coded urgency helps prioritize reorders."),
                ("Metrics", "ADU is Average Daily Usage. The trend arrow compares 30-day vs 90-day ADU. Reorder points are calculated from lead times and safety stock."),
                ("Actions", "Tap Recalculate to refresh all forecasts. Use the lightbulb icon to see AI-generated reorder recommendations."),
            ]
        ),

        HelpEntry(
            pageId: "parts-brands",
            title: "Brands Help",
            sections: [
                ("Overview", "Manage all brands in your parts catalog. Each brand can be linked to multiple parts and suppliers."),
                ("Adding Brands", "Tap the + button to create a new brand. Specify the name, description, and linked suppliers."),
                ("Details", "Tap a brand to view its detail sheet showing linked parts, suppliers, and usage statistics."),
            ]
        ),

        HelpEntry(
            pageId: "parts-suppliers",
            title: "Suppliers Help",
            sections: [
                ("Overview", "Manage your supplier directory. View quality ratings, on-time delivery scores, and the number of parts each supplier provides."),
                ("Adding Suppliers", "Tap + to add a new supplier with contact info, terms, and delivery preferences."),
                ("Sorting & Filtering", "Sort by name, quality, on-time rate, or reliability. Use search to find specific suppliers quickly."),
            ]
        ),

        HelpEntry(
            pageId: "parts-pricing",
            title: "Pricing Help",
            sections: [
                ("Overview", "View and manage pricing for all parts. See cost, markup percentage, and sell price at a glance. Tier badges show where each price comes from."),
                ("Editing", "Tap a part to edit its pricing. Use the menu for bulk edits, tier pricing setup, or global pricing settings."),
                ("Views", "Switch between List, Cards, and Table views using the view mode icon. Filter by category and sort by name, cost, or margin."),
            ]
        ),

        HelpEntry(
            pageId: "parts-companions",
            title: "Companions Help",
            sections: [
                ("Rules", "Companion rules define which parts should always be ordered together. When one part is added to an order, companions are suggested automatically."),
                ("Alternatives", "Alternative parts can substitute for each other. When a part is out of stock, alternatives are suggested as replacements."),
                ("Polls", "Companion polls let the team vote on proposed companion pairings before they become active rules."),
            ]
        ),

        HelpEntry(
            pageId: "parts-categories",
            title: "Categories Help",
            sections: [
                ("Hierarchy", "Parts are organized in a 5-level hierarchy: Category > Style > Type > Brand > Color. Tap any level to drill down."),
                ("Editing", "Select an item in the tree to view and edit its details in the editor panel. On iPad, the editor appears side-by-side."),
                ("Managing", "Add new categories, styles, types, brands, and colors from the editor panel. Changes apply immediately to all parts using that classification."),
            ]
        ),

        // ── ORDERS ────────────────────────────────────────────────────────

        HelpEntry(
            pageId: "orders-jpos",
            title: "Job Purchase Orders Help",
            sections: [
                ("What This Page Does", "Lists all Job Purchase Orders (JPOs) -- requests from field workers for parts they need on the job. Each JPO is tied to a specific job and goes through an approval workflow."),
                ("How to Use It", "Filter by status using the chips at the top (Draft, Pending, Submitted, Approved, Rejected). Search by job name or requester. Tap a JPO to see its line items and take action. Tap + to create a new JPO or scan a QR code to find one."),
                ("Status Flow", "Draft -> Submitted -> Pending (awaiting approval) -> Approved (goes to procurement) or Rejected (sent back with a reason). The pending count badge shows how many need manager attention."),
                ("Tips", "Pull down to refresh. If a JPO shows a question badge, it means a line item is on hold with a pending question from the approver. Tap into the JPO to view and respond to the chat thread."),
            ]
        ),

        HelpEntry(
            pageId: "orders-pos",
            title: "Purchase Orders Help",
            sections: [
                ("What This Page Does", "Lists all purchase orders sent to suppliers. Track POs from draft through ordering, receiving, and completion. See totals, line counts, and delivery status at a glance."),
                ("How to Use It", "Filter by status with the chips at the top (Draft, Submitted, Ordered, Partial, Received, Cancelled). Search by PO number or supplier name. Tap a PO to see full details. Tap + to create a new PO or scan a QR code."),
                ("Sorting", "Use the sort button (arrows icon) to order by newest, oldest, total cost (high/low), supplier name, or status."),
                ("Swipe Actions", "Swipe left on a draft PO to delete it, or swipe left on an active PO to cancel it. Cancellations require a reason. The system generates an AI summary of the PO to help you confirm."),
                ("KPI Bar", "The summary bar shows how many POs are awaiting delivery and the total dollar amount of pending orders. This helps you track outstanding spending."),
                ("Tips", "Pull down to refresh. Status counts in the filter chips update in real time. Tap into a PO to receive shipments, update ETAs, contact the supplier, or report issues."),
            ]
        ),

        HelpEntry(
            pageId: "orders-jpo-create",
            title: "New Parts Order Help",
            sections: [
                ("What This Page Does", "Create a Job Purchase Order (JPO) to request parts for a job. Search for parts, add them to the cart, set quantities, and submit for office approval."),
                ("How to Use It", "Choose the job, priority, and delivery preference. Search or scan parts, add them to the cart, review companion suggestions, add notes, and submit."),
                ("Tips", "Stock colors show whether the shop can transfer parts immediately or whether procurement must order them. The cart total is based on last-known pricing."),
            ]
        ),

        HelpEntry(
            pageId: "orders-jpo-detail",
            title: "JPO Detail Help",
            sections: [
                ("What This Page Does", "Shows one Job Purchase Order with job, requester, priority, delivery preference, status, and line items."),
                ("Status Flow", "Review pending requests, approve or reject lines, inspect holds, and track whether each line is pending, ordered, transferred, or complete."),
                ("Tips", "Use the line summary to understand which parts need approval, supplier ordering, transfer, or follow-up questions."),
            ]
        ),

        HelpEntry(
            pageId: "orders-staging",
            title: "Job Stage Planner Help",
            sections: [
                ("What This Page Does", "Shows all parts across all JPOs for a selected job, grouped by construction stage."),
                ("Held Parts", "Parts assigned to future stages stay held until that stage becomes active, unless a user requests early release."),
                ("Tips", "Use the stage cards to filter the list and see how much work is waiting in each phase."),
            ]
        ),

        HelpEntry(
            pageId: "orders-parts",
            title: "Parts Management Help",
            sections: [
                ("What This Page Does", "Shows all parts ordered from a selected supplier across purchase orders."),
                ("Filters", "Use supplier, PO status, part status, and search filters to narrow the outstanding parts list."),
                ("Tips", "Select rows to prepare supplier-centric follow-up such as moving parts, changing quantities, or holding lines for another supplier."),
            ]
        ),

        HelpEntry(
            pageId: "orders-wishlist",
            title: "Wishlist Help",
            sections: [
                ("What This Page Does", "Tracks parts that should be procured manually or from forecast and system-generated demand."),
                ("Sections", "User Added, Forecast Demand, and System Auto-Added each have different review and approval expectations."),
                ("Tips", "Dismissed items require a reason, and approved items can move into procurement."),
            ]
        ),

        HelpEntry(
            pageId: "orders-unified",
            title: "Unified Order Help",
            sections: [
                ("What This Page Does", "This retired page redirects users conceptually to the current JPO creation workflow."),
                ("Replacement", "Use Job Orders -> Create JPO for new parts requests."),
            ]
        ),

        HelpEntry(
            pageId: "orders-po-detail",
            title: "PO Detail Help",
            sections: [
                ("What This Page Does", "Shows everything about a Purchase Order -- supplier info, line items grouped by job, delivery timeline, cost breakdown, receipt history, and notes. This is where you manage the full lifecycle of a PO."),
                ("Status Actions", "Draft POs can be edited inline (tap a line item to change qty/price) and deleted. Submitted/Ordered POs can be received, have their ETA updated, or be cancelled with a required reason. Partially received POs show what's still outstanding."),
                ("Key Actions", "Receive Shipment: start checking in items. Manage Parts: see all parts for this supplier across POs. Contact Supplier: open a chat channel. Update ETA: set a new expected delivery date. Double Order: re-order remaining items from a different supplier. Report Issue: log a problem."),
                ("Notes Tabs", "The notes section has two tabs -- PO Notes (about this specific order) and Supplier Notes (general notes about the supplier visible on all their POs). Add notes to keep a paper trail."),
                ("Tips", "Swipe left on the PO in the list view to quick-delete drafts or cancel active orders. The cost breakdown section shows subtotal, tax, shipping, and grand total. Receipt history tracks every receiving session."),
            ]
        ),

        HelpEntry(
            pageId: "orders-receiving",
            title: "Receive Shipment Help",
            sections: [
                ("What This Page Does", "Check in parts when a shipment arrives from a supplier. Verify quantities, check prices against the PO, and route each part to its destination (job staging, shelf, or return)."),
                ("How to Use It", "1. Find the PO in the list or scan its QR code.\n2. Tap 'Receive' to start a receiving session.\n3. For each item, set the received quantity (use +/- or tap 'All').\n4. Verify the price -- tap Matches, Different, or Not Shown.\n5. Tap 'Route This Part' to decide where it goes.\n6. When done, tap 'Complete Receiving' to finalize."),
                ("Routing Options", "Stage for Job: send directly to a job's staging area. Put on Shelf: restock the shop inventory. Return: flag for return to supplier. The system suggests routing based on pending job demand and stock levels."),
                ("Price Verification", "If the receipt price differs from the PO price, select 'Different' and enter the actual price. This updates the cost record. 'Not Shown' is for items where the supplier did not include pricing on the packing slip."),
                ("Tips", "The routing progress summary shows how many items you've routed and a breakdown of decisions. You can re-route any item before completing. Tap 'Back' to exit without completing -- your session is saved."),
            ]
        ),

        HelpEntry(
            pageId: "orders-procurement",
            title: "Procurement Help",
            sections: [
                ("What This Page Does", "Aggregates all parts that need to be ordered across all sources -- JPO requests, wishlist items, forecast needs, and overstock alerts. This is where the office decides what to buy and from whom."),
                ("How to Use It", "1. Use the filter cards (JPO Parts, Wishlist, Forecast, Overstock) to focus on one source.\n2. Each part shows demand quantity, current shop stock, and distance to target level.\n3. Select a supplier for each part using the radio buttons.\n4. Check the parts you want to include, then scroll to the PO Preview section.\n5. Review the grouped POs and tap Generate to create them."),
                ("Pull vs Order", "If the shop has stock, you can pull from the shelf instead of ordering. The pull options show how many to pull and how many still need ordering. Overstock items (above MAX level) require a mandatory pull."),
                ("Supplier Tags", "Suppliers show tags: Cheapest (lowest unit price), Best Rated (highest supplier score), Fastest (shortest lead time), and Preferred (star icon, set as default for this part)."),
                ("Split by JPO", "For parts needed by multiple jobs, tap 'Split by JPO' to assign different suppliers per JPO source. Useful when different jobs have different supplier preferences or urgency levels."),
                ("Tips", "Use Select All to quickly include everything. The PO Preview shows grouped totals by supplier before you generate. Parts disappear from this page once POs are created for them."),
            ]
        ),

        HelpEntry(
            pageId: "orders-returns",
            title: "Returns Help",
            sections: [
                ("What This Page Does", "Tracks all part returns to suppliers. Returns can be for wrong parts, damaged items, overstock, or unused materials. Each return has a status, supplier, reason, and credit amount."),
                ("How to Use It", "Use the filter cards to view by status (Pending, Approved, Shipped, Completed). Search by return type, supplier name, or reason. Tap + to create a new return request."),
                ("Return Flow", "Pending -> Approved (supplier accepted the return) -> Shipped (parts sent back) -> Completed (credit received). Each stage updates the credit tracking."),
                ("Tips", "The credit amount shows expected refund value in green. Filter by Pending to see returns that need follow-up with suppliers. Pull down to refresh the list."),
            ]
        ),

        // ── WAREHOUSE ─────────────────────────────────────────────────────

        HelpEntry(
            pageId: "warehouse-dashboard",
            title: "Warehouse Dashboard Help",
            sections: [
                ("Overview", "Monitor warehouse operations at a glance. Smart cards show today's movements, active receiving sessions, audits due, and staging status."),
                ("Filters", "Tap a smart card to filter the activity feed to that category. Tap again to clear the filter."),
                ("Quick Actions", "Use the quick action buttons to start a new movement or scan QR codes for bin lookups."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-inventory",
            title: "Inventory Help",
            sections: [
                ("Overview", "View stock levels at any warehouse location. Color-coded indicators show low stock, out of stock, and healthy levels."),
                ("Location Picker", "Use the picker at the top to switch between warehouse locations, trucks, trailers, and job sites."),
                ("Actions", "Swipe a part row to quickly transfer stock or start an audit. Use the filter chips to focus on problem areas."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-locations",
            title: "Floor Plan Help",
            sections: [
                ("Overview", "Visually map your warehouse with a grid-based floor plan. Place storage units, mark features like doors and walkways."),
                ("Adding Units", "Tap a unit type from the toolbar to add it. Configure dimensions, levels, and areas in the sheet."),
                ("Navigation", "Tap a unit to drill into its levels and areas. Long press for rotate, edit, and remove options."),
                ("Stickers", "After configuring a unit, use the sticker checklist to label all location codes (e.g. R01-U01-S02-A04)."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-staging",
            title: "Staging Area Help",
            sections: [
                ("Overview", "The staging area holds parts that have been pulled from warehouse stock and tagged for specific jobs or destinations."),
                ("Boxes", "Switch to the Boxes tab to manage physical staging boxes. Mark a box as full to auto-create the next one."),
                ("Loading", "Swipe an item or use batch selection to confirm items are loaded onto a truck or delivered to a job site."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-movements",
            title: "Movements Help",
            sections: [
                ("Overview", "Track all stock movements: transfers between locations, receiving from suppliers, returns, and adjustments."),
                ("Creating Movements", "Tap + to start a new guided movement. The wizard walks you through selecting parts, quantities, and locations."),
                ("Filtering", "Use the smart card chips to filter by movement type. Search by part name. Tap any movement for details."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-receiving",
            title: "Receiving Help",
            sections: [
                ("Overview", "Track incoming shipments from suppliers. Each receiving session records what was ordered versus what actually arrived."),
                ("Starting a Session", "Tap + to start receiving against a purchase order. Scan or manually enter received quantities."),
                ("Status Filters", "Use the smart cards to filter by active, completed, or cancelled sessions. Pull down to refresh."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-audit",
            title: "Warehouse Audit Help",
            sections: [
                ("Confidence System", "Each part has a confidence score that decays over time. Auditing confirms shelf accuracy and restores confidence."),
                ("Count Flow", "System counts stay hidden while you count. After submitting, the page shows variance and next steps."),
                ("Misplaced Parts", "Use the misplaced part flow when a part is found in the wrong spot so it can be corrected."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-returns",
            title: "Warehouse Returns Help",
            sections: [
                ("Overview", "Manage supplier return requests through pending, approved, shipped, and completed states."),
                ("Creating Returns", "Tap + to create a return with supplier, parts, and reason details."),
                ("Status Tracking", "Use status filters and search to focus on returns that need follow-up."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-tools",
            title: "Warehouse Tools Help",
            sections: [
                ("Overview", "View tools assigned to the warehouse and see whether they are available, checked out, or in maintenance."),
                ("Actions", "Swipe a row to check out, return, or mark a tool for maintenance when those actions are available."),
                ("Search", "Use search to find tools by name or serial number. Pull down to refresh the list."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-network",
            title: "Network Help",
            sections: [
                ("Overview", "View this device's local warehouse network status and planned connected-device support."),
                ("Sync", "When network sync is available, this page will show real-time connectivity and sync status for local devices."),
                ("Planned", "Planned capabilities include LAN HTTP sync, peer-to-peer pairing, encrypted sync, and conflict resolution."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-settings",
            title: "Warehouse Settings Help",
            sections: [
                ("Locations", "Configure default receiving and staging locations used when new shipments arrive or parts are pulled."),
                ("Thresholds", "Set low stock and critical stock thresholds and choose whether alerts are enabled."),
                ("Policies", "Control movement notes, approvals, auto-confirm thresholds, audit frequency, and discrepancy photo requirements."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-organization",
            title: "Organization Audit Help",
            sections: [
                ("Organization Ratings", "Each area gets a rating based on labels, part placement, duplicate storage, overcrowding, and bin assignment."),
                ("Consolidation", "When the same part is spread across too many areas, the page suggests consolidation and tracks votes."),
                ("Org Checklist", "Tap an area to run a checklist for labels, part placement, duplicate cleanup, space, and bin assignment."),
            ]
        ),

        HelpEntry(
            pageId: "warehouse-leaderboard",
            title: "Leaderboard Help",
            sections: [
                ("Ratings", "Warehouse ratings summarize user accuracy, effort, placement, speed, and proactive fixes."),
                ("Scores", "Scores range from 0 to 10. Accurate counts and clean placement raise scores; misplacements lower them."),
                ("Managers", "Managers can open user details for score breakdowns and training suggestions."),
            ]
        ),

        // ── SCHEDULING ────────────────────────────────────────────────────

        HelpEntry(
            pageId: "scheduling-dispatch",
            title: "Dispatch Board Help",
            sections: [
                ("What This Page Does", "The Dispatch Board is a Gantt-style weekly view showing which workers are assigned to which jobs each day. Colored bars indicate time slots: blue for AM, green for PM, and orange for full day."),
                ("How to Use It", "Navigate between weeks using the left/right arrows. Tap an empty cell on a job row to assign a worker to that job and day. Tap a worker in the Unassigned section to start an assignment for them. Use the + button to create a new assignment from scratch."),
                ("Time-Off Conflicts", "If you assign someone who has approved time off that day, you will see a conflict warning. You can choose to assign them anyway or cancel."),
                ("Tips", "Red 'Unassigned Workers' at the bottom means people have no work scheduled that week. Aim to keep this section empty by assigning everyone to jobs."),
            ]
        ),

        HelpEntry(
            pageId: "scheduling-calendar",
            title: "Schedule Calendar Help",
            sections: [
                ("What This Page Does", "The Schedule Calendar shows your work assignments in either a week list or a month grid. Month view uses colored dots to indicate AM (blue), PM (green), full-day (orange), and time-off (red) entries for each day."),
                ("How to Use It", "Toggle between Week and Month views using the segmented control at the top. In month view, tap any day to see its detail below the calendar. In week view, scroll through the list of assignments. Use the + button to create a new schedule entry."),
                ("Color Coding", "Blue dots and badges mean AM shifts, green means PM, orange means full day. Red dots indicate someone has time off that day."),
                ("Tips", "Pull down to refresh the schedule. Use the search bar to filter entries by job name or notes. Navigate between weeks or months using the arrow buttons."),
            ]
        ),

        // ── PEOPLE ────────────────────────────────────────────────────────

        HelpEntry(
            pageId: "people-employees",
            title: "Employees Help",
            sections: [
                ("What This Page Does", "View and manage all employees in the system. Each row shows the employee's name, email, assigned hats (roles), status, and role level."),
                ("How to Use It", "Use the status filter chips at the top to show only Active, Inactive, or Suspended employees. Type in the search bar to filter by name, email, phone, or hat. Tap an employee to view their full profile. Tap the + button to add a new employee."),
                ("Badge Scanner", "Tap the QR scanner icon to scan an employee badge. If the badge is found, the employee's name fills the search bar automatically."),
                ("Tips", "Pull down to refresh the list. Status badges are color-coded: green for active, red for suspended, gray for inactive. Role badges show the employee's access level (admin, manager, supervisor, or worker)."),
            ]
        ),

        HelpEntry(
            pageId: "people-dashboard",
            title: "People Dashboard Help",
            sections: [
                ("What This Page Does", "The People Dashboard gives you a real-time overview of your workforce. See who is clocked in, who is off today, which certifications are expiring, and which teams are assigned to jobs."),
                ("How to Use It", "The smart cards at the top summarize key numbers at a glance. Scroll down to see details for Working Now, Off Today, Certifications Expiring Soon, and Team Assignments Today."),
                ("Payment Alerts", "When payment tracking is enabled, overdue customer invoices appear at the bottom with the amount and number of days overdue."),
                ("Tips", "Pull down to refresh the dashboard with the latest data. Tap into other People pages from the navigation menu to manage employees, customers, contractors, teams, and contacts."),
            ]
        ),

        HelpEntry(
            pageId: "people-customers",
            title: "Customers Help",
            sections: [
                ("What This Page Does", "View and manage all customers. Each row shows the company name, primary contact, email, and phone number."),
                ("How to Use It", "Type in the search bar to filter customers by company name, contact name, or email. Tap a customer to see their full detail page with contacts, job history, billing, and communication logs. Tap the + button to add a new customer."),
                ("Adding a Customer", "The contact name is required. You can also add a company name, email, phone, and address. Customers appear in the list immediately after saving."),
                ("Tips", "Pull down to refresh the customer list. Tap into a customer to add additional contacts, record payments, or log communications like calls and meetings."),
            ]
        ),

        HelpEntry(
            pageId: "people-contacts",
            title: "Contacts Help",
            sections: [
                ("What This Page Does", "View and manage all contacts across your organization. Contacts include GCs, suppliers, contractors, owners, vendors, and other external people you work with."),
                ("Smart Card Filters", "Tap the type cards at the top to filter by contact type: All, GC, Supplier, Contractor, Owner, Vendor, Active, or Inactive. The count on each card shows how many contacts match that type."),
                ("Sorting & Search", "Use the sort button to order contacts by Recently Updated, Name, or Type. The search bar filters by first name, last name, company, or email."),
                ("Tips", "Pull down to refresh. Contact type badges are color-coded by type. Tap the + button to add a new contact with a first name and phone number."),
            ]
        ),

        HelpEntry(
            pageId: "people-employee-detail",
            title: "Employee Detail Help",
            sections: [
                ("What This Page Does", "View and edit a single employee's profile, hat assignments, and team memberships. Use the tabs to switch between Profile, Hats, and Teams views."),
                ("Profile Tab", "Shows the employee's basic info: name, email, phone, role, status, and important dates. Tap Edit in the toolbar to update their contact information."),
                ("Hats Tab", "Displays all available hats (roles) and which ones are assigned to this employee. If you have manage_people permission, you can toggle hats on and off directly. Each hat grants a set of permissions."),
                ("Teams Tab", "Shows which teams this employee belongs to, their role within each team, and when they joined."),
                ("Tips", "Pull down to refresh all data. Only managers and admins can toggle hat assignments. The Edit button updates contact info only — use the Hats tab for role changes."),
            ]
        ),

        // ── FLEET ─────────────────────────────────────────────────────────

        HelpEntry(
            pageId: "fleet-dashboard",
            title: "Fleet Dashboard Help",
            sections: [
                ("Overview", "The Fleet Dashboard gives you a bird's-eye view of every vehicle, trailer, and maintenance item in the fleet. Smart cards at the top show key counts at a glance."),
                ("Status Cards", "The first row shows total vehicles, how many are active, how many have maintenance due, overdue inspections, and total trailers. Tap to scan quickly for anything that needs attention."),
                ("Cost Cards", "If you have financial permissions, a second row shows month-to-date fuel spend, miles driven, and maintenance costs. These update as new logs are entered."),
                ("Vehicle List", "Scroll down to see every vehicle with its current driver, status, and whether today's pre-trip inspection has been completed. Tap a vehicle to open its detail page."),
                ("Upcoming Maintenance", "Shows vehicles with scheduled maintenance approaching. Overdue items appear in red so nothing slips through the cracks."),
                ("Tips", "Pull down to refresh data at any time. Check this dashboard at the start of each day to spot overdue inspections and upcoming maintenance before trucks roll out."),
            ]
        ),

        HelpEntry(
            pageId: "fleet-vehicles",
            title: "Vehicles Help",
            sections: [
                ("Overview", "This page lists all vehicles in the fleet. Each row shows the vehicle number, name, make/model, type, status, assigned driver, and current odometer reading."),
                ("Filtering", "Use the status pills at the top to filter by Active, Inactive, Maintenance, or Retired vehicles. Tap All to see everything. Use the search bar to find vehicles by name, number, make, model, or driver."),
                ("Adding a Vehicle", "Tap the + button in the top-right corner to add a new vehicle. You need the manage_fleet permission to add vehicles."),
                ("Vehicle Detail", "Tap any vehicle row to open its detail page with tabs for overview, parts, tools, assignments, maintenance, usage, and inspections."),
                ("Tips", "Pull down to refresh the list. Status badges are color-coded: green for active, orange for maintenance, red for retired, and gray for inactive."),
            ]
        ),

        HelpEntry(
            pageId: "fleet-maintenance",
            title: "Maintenance Help",
            sections: [
                ("Overview", "This page lists all maintenance records across the fleet. Each record shows the vehicle, type of service performed, date, who did the work, cost, and odometer reading at the time."),
                ("Searching", "Use the search bar to filter by vehicle name, maintenance type, or technician name. This helps you quickly find service history for a specific truck."),
                ("Reading Entries", "The orange wrench icon marks each record. Vehicle name and maintenance type appear on the left. Cost and mileage appear on the right."),
                ("Tips", "Regular maintenance keeps trucks on the road. Check this page to verify completed services and track spending. The Fleet Dashboard also highlights upcoming and overdue maintenance items."),
            ]
        ),

        // ── TOOLS ─────────────────────────────────────────────────────────

        HelpEntry(
            pageId: "tools-registry",
            title: "All Tools Help",
            sections: [
                ("What This Page Does", "The All Tools is the master inventory of every tool the company owns. Each entry shows the tool name, number, category, serial number, who it is assigned to, current status, and value."),
                ("Searching & Filtering", "Use the search bar to find tools by name, tool number, serial number, or assignee. Tap the status pills at the top (All, Available, Checked Out, Maintenance, Lost) to filter the list by current status."),
                ("QR Scanner", "Tap the QR code icon in the toolbar to scan a tool's QR label. The scanned tool will appear in your search results automatically."),
                ("Printing Labels", "Tap the printer icon to generate QR labels for the currently visible tools. You can print labels for the entire filtered list at once."),
                ("Tool Details", "Tap any tool row to open its full detail page where you can check it out, return it, edit its info, or report an issue."),
                ("Tips", "Tools with a red 'Lost' badge need investigation. Orange 'Maintenance' tools are out of service. Green 'Available' tools are ready for checkout."),
            ]
        ),

        // ── NOTEBOOKS ─────────────────────────────────────────────────────

        HelpEntry(
            pageId: "notebooks-all",
            title: "Notebooks Help",
            sections: [
                ("What This Page Does", "Displays all notebooks in the system. Notebooks are organized documents that hold structured entries such as text blocks, checklists, photos, and part references. They can be general-purpose or linked to specific jobs."),
                ("How to Use It", "Use the type filter chips at the top to narrow by notebook type (General, Job, Daily Report, or Checklist). Use the search bar to find notebooks by title, job name, or author. Tap a notebook to view its full contents. Pull down to refresh the list."),
                ("Creating a Notebook", "Tap the + button in the toolbar to create a new notebook. You can choose a type, assign it to a job, and optionally start from a template."),
                ("Notebook Types", "General notebooks are standalone. Job notebooks are linked to a specific job. Daily Report notebooks track daily progress. Checklist notebooks contain to-do items that can be checked off."),
            ]
        ),

        // ── OFFICE ────────────────────────────────────────────────────────

        HelpEntry(
            pageId: "office-dashboard",
            title: "Office Dashboard Help",
            sections: [
                ("What This Page Does", "Your morning command center. Shows an AI-generated daily briefing, items that need your attention (color-coded by priority), today's crew schedule, a financial snapshot, and background task status."),
                ("How to Use It", "Pull down to refresh all sections. The AI briefing updates hourly and highlights key things you should know. Attention items are sorted by urgency: red means overdue, orange is high priority. The financial snapshot compares this week and month to previous periods so you can spot spending trends."),
                ("Financial Snapshot", "Only visible if you have the 'view financials' permission. Shows weekly and monthly spend with comparisons to the prior period, plus outstanding PO value."),
                ("Tips", "Check this page first thing each morning. The briefing and attention items give you a quick read on what matters today without digging through individual pages."),
            ]
        ),

        HelpEntry(
            pageId: "office-approvals",
            title: "Unified Approvals Help",
            sections: [
                ("What This Page Does", "Shows all items waiting for manager approval in one place. This includes JPO requests from field workers, scheduled part deletions, time-off requests, and tool edit verifications."),
                ("How to Use It", "Use the filter cards at the top to narrow by type (JPOs, Deletions, Time-Off, Tool Edits). Search by name or requester. For each item, tap Approve or Reject. Rejections require a reason that gets sent back to the requester."),
                ("Tips", "Pull down to refresh the list. Items disappear from this page once approved or rejected. If you reject a JPO, the field worker gets notified with your reason so they can revise and resubmit. This same page is accessible from both Office > Approvals and Orders > Approvals."),
            ]
        ),

        HelpEntry(
            pageId: "office-spending",
            title: "Spending Dashboard Help",
            sections: [
                ("Overview", "Aggregate spending data across all jobs. See total parts costs, labor costs, and budget utilization at a glance."),
                ("Breakdown", "Cards show spending by category. Tap for detailed breakdowns by job, supplier, or time period."),
                ("Permissions", "This page requires the show dollar values permission. Contact your admin if you cannot see cost data."),
            ]
        ),

        // ── REPORTS ───────────────────────────────────────────────────────

        HelpEntry(
            pageId: "reports-labor",
            title: "Labor Overview Help",
            sections: [
                ("What This Page Does", "Gives you a high-level view of labor for the current week. Shows total hours, regular vs overtime, and the number of active workers. Below that, each employee is listed with their individual breakdown."),
                ("How to Use It", "The top section shows weekly totals. Scroll down to see each employee's regular hours, overtime, and days worked. Pull down to refresh if crews are still clocking in."),
                ("Tips", "Keep an eye on overtime numbers. If someone is already high mid-week, consider adjusting schedules. This report resets each Monday."),
            ]
        ),

        HelpEntry(
            pageId: "reports-spending",
            title: "Spending Help",
            sections: [
                ("What This Page Does", "Shows how much money has been spent on purchase orders over a time window. Displays total spend, number of POs, average PO amount, and your top supplier by dollar volume."),
                ("How to Use It", "Tap a time period button (7d, 14d, 30d, etc.) to change the lookback window. The four KPI cards update automatically. Pull down to refresh if new POs have been submitted."),
                ("Tips", "Use the 30-day view for monthly budget checks. If the top supplier keeps changing, it might mean you are spreading orders too thin. Consolidating with fewer suppliers can get better pricing."),
            ]
        ),

        HelpEntry(
            pageId: "reports-profitability",
            title: "Profitability Help",
            sections: [
                ("What This Page Does", "Shows how much profit each job is making. For every job, you see revenue, labor cost, material cost, total profit, and margin percentage. Green means healthy, red means losing money."),
                ("How to Use It", "Scroll through the list to see all jobs. Use the search bar to find a specific job. The margin badge on the right gives you a quick color-coded indicator: green is 20%+, orange is break-even, red is a loss."),
                ("Tips", "Focus on jobs with orange or red margins first. If a job's labor cost is unusually high, check if overtime is driving it up. Export this report to share with management during job reviews."),
            ]
        ),

        HelpEntry(
            pageId: "reports-timesheets",
            title: "Timesheets Help",
            sections: [
                ("What This Page Does", "Lists every employee's timesheet totals for the selected date range. Shows regular hours, overtime hours, total hours, and how many days each person worked."),
                ("How to Use It", "Set the start and end dates to match the period you want to review. Use the search bar to find a specific employee. Each row shows their name, hours breakdown, and days worked. Export to PDF or CSV using the toolbar button."),
                ("Tips", "Run this for each pay period before submitting payroll. If someone's hours seem too low, they may have forgotten to clock in. Compare against daily reports to catch missing entries."),
            ]
        ),

        HelpEntry(
            pageId: "reports-prebilling",
            title: "Pre-Billing Help",
            sections: [
                ("What This Page Does", "Summarizes labor hours per job for the selected date range so you can review them before sending invoices. Shows regular and overtime hours side by side for each job."),
                ("How to Use It", "Set the start and end dates to match your billing period. Review each job's hours. The top cards show totals across all jobs. Use the export button to generate a PDF or CSV for your billing workflow."),
                ("Tips", "Run this report before finalizing invoices. Compare the totals here against your job estimates to catch any billing surprises early. If hours look wrong, check the Timesheets page for details."),
            ]
        ),

        HelpEntry(
            pageId: "reports-bookkeeper",
            title: "Bookkeeper Export Help",
            sections: [
                ("What This Page Does", "Shows a summary of labor hours per employee and material purchase orders for the date range you pick. This is the data your bookkeeper needs for payroll and expense tracking."),
                ("How to Use It", "Pick a start and end date at the top. The page loads labor totals (regular and overtime hours by employee) and material POs (supplier, PO number, and amount). Use the export button to send a PDF or CSV to your bookkeeper."),
                ("Tips", "Set dates to match your pay period for clean exports. If an employee is missing, check that their clock entries exist for that date range."),
            ]
        ),

        HelpEntry(
            pageId: "reports-daily-summary",
            title: "Daily Reports Summary Help",
            sections: [
                ("What This Page Does", "Shows a quick snapshot of all daily reports across every active job for a single day. You can see how many workers were on each job, total hours logged, and the job status."),
                ("How to Use It", "Use the left and right arrows to move between days, or tap the date to pick a specific day. Each row shows a job with worker count, hours, and status. The top KPIs give you totals at a glance."),
                ("Tips", "Check this page at the end of each workday to make sure all jobs have reports filed. If a job shows zero workers, the foreman may not have submitted the daily report yet."),
            ]
        ),
    ]
}
