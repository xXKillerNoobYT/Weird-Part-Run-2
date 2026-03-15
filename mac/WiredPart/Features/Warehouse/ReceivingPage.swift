import SwiftUI
import GRDB
import WiredPartCore

/// Receiving sessions management page.
///
/// Shows active receiving sessions, allows starting new sessions from POs,
/// displays session items with expected vs received quantities, and provides
/// inline editing of received_qty. Sessions can be completed or cancelled.
struct ReceivingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var activeSessions: [SessionRow] = []
    @State private var completedSessions: [SessionRow] = []
    @State private var availablePOs: [PORow] = []
    @State private var isLoading = true

    // MARK: - Session Detail

    @State private var selectedSession: SessionRow?
    @State private var sessionItems: [SessionItemRow] = []
    @State private var showSessionDetail = false

    // MARK: - New Session

    @State private var showNewSession = false
    @State private var selectedPOId: Int64?

    // MARK: - Confirm Actions

    @State private var showCompleteConfirm = false
    @State private var showCancelConfirm = false
    @State private var actionSessionId: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                activeSessionsSection
                Divider()
                completedSessionsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .sheet(isPresented: $showSessionDetail) {
            if let session = selectedSession {
                sessionDetailSheet(session)
            }
        }
        .sheet(isPresented: $showNewSession) {
            newSessionSheet
        }
        .alert("Complete Session", isPresented: $showCompleteConfirm) {
            Button("Complete", role: .destructive) {
                if let id = actionSessionId { completeSession(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark this receiving session as complete? This finalizes all quantities.")
        }
        .alert("Cancel Session", isPresented: $showCancelConfirm) {
            Button("Cancel Session", role: .destructive) {
                if let id = actionSessionId { cancelSession(id) }
            }
            Button("Keep Open", role: .cancel) {}
        } message: {
            Text("Cancel this receiving session? Items will not be counted as received.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Receiving")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(activeSessions.count) active session\(activeSessions.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                loadAvailablePOs()
                selectedPOId = nil
                showNewSession = true
            } label: {
                Label("Start Session", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Active Sessions

    @ViewBuilder
    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Sessions")
                .font(.headline)

            if isLoading {
                ProgressView("Loading sessions...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if activeSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No active receiving sessions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(activeSessions, id: \.id) { session in
                        sessionCard(session, isActive: true)
                    }
                }
            }
        }
    }

    // MARK: - Completed Sessions

    @ViewBuilder
    private var completedSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed Sessions")
                .font(.headline)

            if completedSessions.isEmpty {
                Text("No completed sessions yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(completedSessions.prefix(20), id: \.id) { session in
                        sessionCard(session, isActive: false)
                    }
                }
            }
        }
    }

    private func sessionCard(_ session: SessionRow, isActive: Bool) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "shippingbox.and.arrow.backward.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isActive ? Color.blue : Color.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.poNumber)
                        .font(.callout)
                        .fontWeight(.medium)
                    HStack(spacing: 8) {
                        Text(session.supplierName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.status.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isActive ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                            .foregroundStyle(isActive ? Color.blue : Color.green)
                            .clipShape(Capsule())
                    }
                    HStack(spacing: 8) {
                        Label(session.startedByName, systemImage: "person")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(formatDate(session.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button("View") {
                    selectedSession = session
                    loadSessionItems(session.id)
                    showSessionDetail = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Session Detail Sheet

    private func sessionDetailSheet(_ session: SessionRow) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Receiving: \(session.poNumber)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(session.supplierName) - \(session.status.capitalized)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showSessionDetail = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            if sessionItems.isEmpty {
                Text("No items in this session")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        // Header
                        HStack {
                            Text("Part")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Expected")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 80)
                            Text("Received")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 80)
                            Text("Status")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 80)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)

                        ForEach(Array(sessionItems.enumerated()), id: \.element.id) { index, item in
                            sessionItemRow(item, index: index, isActive: session.status == "in_progress")
                        }
                    }
                }
            }

            if session.status == "in_progress" {
                Divider()
                HStack {
                    Button("Cancel Session") {
                        actionSessionId = session.id
                        showSessionDetail = false
                        showCancelConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Spacer()

                    Button("Complete Session") {
                        actionSessionId = session.id
                        showSessionDetail = false
                        showCompleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 400)
    }

    private func sessionItemRow(_ item: SessionItemRow, index: Int, isActive: Bool) -> some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.partName)
                        .font(.callout)
                        .fontWeight(.medium)
                    if !item.partCode.isEmpty {
                        Text(item.partCode)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(item.expectedQty)")
                    .font(.callout)
                    .frame(width: 80)

                if isActive {
                    TextField("", value: Binding(
                        get: { item.receivedQty },
                        set: { newValue in updateItemQty(itemId: item.id, qty: newValue) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
                } else {
                    Text("\(item.receivedQty)")
                        .font(.callout)
                        .frame(width: 80)
                }

                itemStatusBadge(expected: item.expectedQty, received: item.receivedQty)
                    .frame(width: 80)
            }
            .padding(.vertical, 2)
        }
    }

    private func itemStatusBadge(expected: Int, received: Int) -> some View {
        let (label, color): (String, Color) = {
            if received == 0 { return ("Pending", .gray) }
            if received >= expected { return ("Complete", .green) }
            return ("Partial", .orange)
        }()

        return Text(label)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - New Session Sheet

    private var newSessionSheet: some View {
        VStack(spacing: 16) {
            Text("Start Receiving Session")
                .font(.headline)

            if availablePOs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No eligible purchase orders")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("POs with status 'ordered' or 'partially received' will appear here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 20)
            } else {
                Picker("Purchase Order", selection: $selectedPOId) {
                    Text("Select a PO...").tag(nil as Int64?)
                    ForEach(availablePOs, id: \.id) { po in
                        Text("\(po.poNumber) - \(po.supplierName)")
                            .tag(po.id as Int64?)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Button("Cancel") { showNewSession = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    if let poId = selectedPOId {
                        startNewSession(poId: poId)
                    }
                    showNewSession = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPOId == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    // MARK: - Helpers

    nonisolated private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "-" }
        if dateStr.count >= 16 {
            return String(dateStr.prefix(16))
        }
        return dateStr
    }

    // MARK: - Actions

    private func startNewSession(poId: Int64) {
        guard let db = appCore.db, let userId = appCore.currentUser?.id else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: """
                        INSERT INTO receiving_sessions (po_id, started_by, mode, status, created_at)
                        VALUES (?, ?, 'packing_slip', 'in_progress', datetime('now'))
                        """,
                    arguments: [poId, userId]
                )
                let sessionId = conn.lastInsertedRowID

                // Auto-populate items from PO line items
                let poLines = try Row.fetchAll(conn, sql: """
                    SELECT id, qty_ordered FROM po_line_items
                    WHERE po_id = ? AND deleted_at IS NULL
                    """, arguments: [poId])

                for line in poLines {
                    let lineId: Int64 = line["id"]
                    let qtyOrdered: Int = line["qty_ordered"] ?? 0
                    try conn.execute(
                        sql: """
                            INSERT INTO receiving_session_items (session_id, po_line_id, expected_qty, received_qty, created_at)
                            VALUES (?, ?, ?, 0, datetime('now'))
                            """,
                        arguments: [sessionId, lineId, qtyOrdered]
                    )
                }
            }
        } catch {
            print("[ReceivingPage] Start session error: \(error)")
        }
        loadData()
    }

    private func completeSession(_ sessionId: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE receiving_sessions SET status = 'completed', completed_at = datetime('now') WHERE id = ?",
                    arguments: [sessionId]
                )
            }
        } catch {
            print("[ReceivingPage] Complete error: \(error)")
        }
        loadData()
    }

    private func cancelSession(_ sessionId: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE receiving_sessions SET status = 'cancelled', completed_at = datetime('now') WHERE id = ?",
                    arguments: [sessionId]
                )
            }
        } catch {
            print("[ReceivingPage] Cancel error: \(error)")
        }
        loadData()
    }

    private func updateItemQty(itemId: Int64, qty: Int) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE receiving_session_items SET received_qty = ? WHERE id = ?",
                    arguments: [qty, itemId]
                )
            }
            // Refresh session items
            if let session = selectedSession {
                loadSessionItems(session.id)
            }
        } catch {
            print("[ReceivingPage] Update qty error: \(error)")
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                let sessionSql = """
                    SELECT rs.id, rs.po_id, rs.status, rs.mode, rs.created_at, rs.completed_at,
                           COALESCE(po.po_number, 'Unknown') AS po_number,
                           COALESCE(sup.name, '') AS supplier_name,
                           COALESCE(u.display_name, '') AS started_by_name
                    FROM receiving_sessions rs
                    LEFT JOIN purchase_orders po ON po.id = rs.po_id
                    LEFT JOIN suppliers sup ON sup.id = po.supplier_id
                    LEFT JOIN users u ON u.id = rs.started_by
                    WHERE rs.deleted_at IS NULL
                    ORDER BY rs.created_at DESC
                    """

                let rows = try Row.fetchAll(conn, sql: sessionSql)
                let sessions = rows.map { row in
                    SessionRow(
                        id: row["id"] ?? 0,
                        poId: row["po_id"] ?? 0,
                        poNumber: row["po_number"] ?? "Unknown",
                        supplierName: row["supplier_name"] ?? "",
                        startedByName: row["started_by_name"] ?? "",
                        status: row["status"] ?? "",
                        mode: row["mode"] ?? "",
                        createdAt: row["created_at"],
                        completedAt: row["completed_at"]
                    )
                }

                activeSessions = sessions.filter { $0.status == "in_progress" }
                completedSessions = sessions.filter { $0.status != "in_progress" }
            }
        } catch {
            print("[ReceivingPage] Load error: \(error)")
        }

        isLoading = false
    }

    private func loadAvailablePOs() {
        guard let db = appCore.db else { return }
        do {
            try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT po.id, po.po_number,
                           COALESCE(sup.name, '') AS supplier_name
                    FROM purchase_orders po
                    LEFT JOIN suppliers sup ON sup.id = po.supplier_id
                    WHERE po.deleted_at IS NULL
                      AND po.status IN ('ordered', 'partially_received', 'submitted', 'acknowledged')
                    ORDER BY po.created_at DESC
                    """)

                availablePOs = rows.map { row in
                    PORow(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? ""
                    )
                }
            }
        } catch {
            print("[ReceivingPage] Load POs error: \(error)")
        }
    }

    private func loadSessionItems(_ sessionId: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT rsi.id, rsi.expected_qty, rsi.received_qty, rsi.notes,
                           COALESCE(p.name, 'Unknown Part') AS part_name,
                           COALESCE(p.code, '') AS part_code
                    FROM receiving_session_items rsi
                    LEFT JOIN po_line_items pli ON pli.id = rsi.po_line_id
                    LEFT JOIN parts p ON p.id = pli.part_id
                    WHERE rsi.session_id = ? AND rsi.deleted_at IS NULL
                    ORDER BY p.name ASC
                    """, arguments: [sessionId])

                sessionItems = rows.map { row in
                    SessionItemRow(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] ?? "",
                        expectedQty: row["expected_qty"] ?? 0,
                        receivedQty: row["received_qty"] ?? 0,
                        notes: row["notes"] ?? ""
                    )
                }
            }
        } catch {
            print("[ReceivingPage] Load items error: \(error)")
        }
    }
}

// MARK: - Display Models

private struct SessionRow: Identifiable {
    let id: Int64
    let poId: Int64
    let poNumber: String
    let supplierName: String
    let startedByName: String
    let status: String
    let mode: String
    let createdAt: String?
    let completedAt: String?
}

private struct SessionItemRow: Identifiable {
    let id: Int64
    let partName: String
    let partCode: String
    let expectedQty: Int
    let receivedQty: Int
    let notes: String
}

private struct PORow: Identifiable {
    let id: Int64
    let poNumber: String
    let supplierName: String
}
