-- ═══════════════════════════════════════════════════════════════════════
-- Migration 019: Orders Redesign Phase 7B — Office Workflow
--
-- New tables: po_conversations, po_groups, po_group_members
-- Altered: purchase_orders (add confirmation_checklist, supplier_notes)
--
-- Provides: conversation threading per PO, PO grouping for bundled
-- sending, and a per-line confirmation checklist for office staff.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════
-- 1. PO CONVERSATIONS — CRM-style thread per PO
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS po_conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER REFERENCES purchase_orders(id) ON DELETE CASCADE,
    supplier_id INTEGER REFERENCES suppliers(id),
    entry_type TEXT NOT NULL
        CHECK (entry_type IN ('note', 'call', 'email_summary', 'action', 'system')),
    message TEXT NOT NULL,
    follow_up_needed INTEGER NOT NULL DEFAULT 0,
    follow_up_resolved_at TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_po_conv_po ON po_conversations(po_id, created_at);
CREATE INDEX IF NOT EXISTS idx_po_conv_supplier ON po_conversations(supplier_id, created_at);
CREATE INDEX IF NOT EXISTS idx_po_conv_followup ON po_conversations(follow_up_needed, follow_up_resolved_at);


-- ═══════════════════════════════════════════════════════════
-- 2. PO GROUPS — bundle multiple POs for combined sending
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS po_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_name TEXT,
    supplier_id INTEGER REFERENCES suppliers(id),
    created_by INTEGER REFERENCES users(id),
    pdf_path TEXT,                  -- path to combined PDF
    individual_pdfs TEXT,           -- JSON array of individual PDF paths
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS po_group_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER NOT NULL REFERENCES po_groups(id) ON DELETE CASCADE,
    po_id INTEGER NOT NULL REFERENCES purchase_orders(id),
    UNIQUE(group_id, po_id)
);

CREATE INDEX IF NOT EXISTS idx_po_group_members_group ON po_group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_po_group_members_po ON po_group_members(po_id);


-- ═══════════════════════════════════════════════════════════
-- 3. ALTER purchase_orders — add confirmation & supplier notes
-- ═══════════════════════════════════════════════════════════

-- JSON column: [{part_id, confirmed, confirmed_by, confirmed_at}]
ALTER TABLE purchase_orders ADD COLUMN confirmation_checklist TEXT;

-- Free-text notes specific to supplier communication
ALTER TABLE purchase_orders ADD COLUMN supplier_notes TEXT;
