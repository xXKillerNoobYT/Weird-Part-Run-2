/**
 * helpContent — centralized help text for contextual help buttons.
 *
 * Each key maps to a section of the app. The HelpButton component
 * looks up the key and renders the title + body in a tooltip/popover.
 *
 * Keeping help text in one file makes it easy to update copy
 * without touching component code. Add new keys as needed.
 *
 * Phase 7E
 */

export interface HelpEntry {
  title: string;
  body: string;
  /** Optional link label for "Learn more" */
  linkLabel?: string;
  /** Optional link URL (future: could point to a docs page) */
  linkUrl?: string;
}

const helpContent: Record<string, HelpEntry> = {
  // ── Orders ────────────────────────────────────────────────

  'orders.unified-form': {
    title: 'Order Types',
    body: 'Job Orders are tied to a specific job and go through approval. Warehouse Restocking orders replenish general inventory without job assignment.',
  },

  'orders.smart-suggestions': {
    title: 'Smart Suggestions',
    body: 'When enabled, the system remembers which brands, colors, and suppliers were used on previous orders for this job. Toggle each category on/off to filter your part search.',
  },

  'orders.special-items': {
    title: 'Special Items',
    body: 'Items not in the parts catalog can be added as special items. They are automatically flagged for office review. The office team can match them to catalog parts or order them directly.',
  },

  'orders.status-draft': {
    title: 'Draft Status',
    body: 'Draft orders are saved but not yet submitted. You can continue editing them at any time. Submit when ready for approval.',
  },

  'orders.status-pending': {
    title: 'Pending Approval',
    body: 'This order has been submitted and is waiting for a manager to review and approve it. You\'ll receive a notification when it\'s approved or if changes are needed.',
  },

  'orders.status-approved': {
    title: 'Approved',
    body: 'This order has been approved by a manager. The office team will create purchase orders for the items and send them to suppliers.',
  },

  'orders.bulk-actions': {
    title: 'Bulk Actions',
    body: 'Use the checkboxes to select multiple items, then use the action bar at the bottom to perform actions on all selected items at once.',
  },

  // ── Purchase Orders ───────────────────────────────────────

  'po.confirmation-checklist': {
    title: 'Confirmation Checklist',
    body: 'Check off each item as you confirm it\'s been ordered with the supplier. This helps track which items are confirmed vs still pending confirmation.',
  },

  'po.conversation': {
    title: 'Conversation Thread',
    body: 'Keep a record of all communications with the supplier about this PO. Add notes from phone calls, email summaries, or internal comments. Flag entries that need follow-up.',
  },

  'po.review-and-send': {
    title: 'Review & Send',
    body: 'Review approved order lines grouped by supplier. You can bundle multiple job orders into a single PO for efficiency. Generate PDFs individually or as a combined document.',
  },

  // ── Receiving ─────────────────────────────────────────────

  'receiving.packing-slip': {
    title: 'Packing Slip Mode',
    body: 'Enter the PO number to see all expected items. Enter the received quantity for each line item as you check them against the packing slip. No need to scan individual items.',
  },

  'receiving.scan-mode': {
    title: 'Scan Mode',
    body: 'Scan the QR code on each item to find the matching PO line. Enter the received quantity after each scan. Useful when items arrive without a packing slip.',
  },

  'receiving.staging': {
    title: 'Staging Zones',
    body: 'Assign received items to staging zones for organized distribution. Items can be picked up by field workers or moved to permanent storage from the staging zone.',
  },

  // ── Returns ───────────────────────────────────────────────

  'returns.sorting': {
    title: 'Return Sorting',
    body: 'Each returned item needs a disposition: return to supplier (if eligible), keep in warehouse (if below target), or write off (if damaged/used). The system helps guide these decisions.',
  },

  'returns.eligibility': {
    title: 'Return Eligibility',
    body: 'Items are checked for supplier return eligibility based on condition and supplier policies. Items that have been opened, used, or custom-modified typically cannot be returned to suppliers.',
  },

  'returns.below-target': {
    title: 'Below Target Warning',
    body: 'When the warehouse quantity for this part is below the restock target, the system suggests keeping the item instead of returning it to the supplier.',
  },

  // ── Cost Tracking ─────────────────────────────────────────

  'costs.weighted-average': {
    title: 'Weighted Average Cost',
    body: 'The system tracks costs using a company-wide weighted average. Each time new inventory is received at a different price, the average cost is recalculated based on all remaining inventory.',
  },

  'costs.margin': {
    title: 'Margin Settings',
    body: 'Each part has a margin applied to its cost to determine the sell price. You can set a custom margin per part or use the company default. The "Enforce Default" button resets all custom margins.',
  },

  'costs.fifo-lifo': {
    title: 'FIFO / LIFO',
    body: 'When parts are consumed (used on jobs), the oldest inventory layers are used first (FIFO). When parts are returned, the newest layers are restored first (LIFO). This ensures accurate cost tracking.',
  },

  // ── QR & Images ───────────────────────────────────────────

  'parts.qr-images': {
    title: 'QR Code Images',
    body: 'When linking a QR code to a part, you must upload two photos: one of the device/part itself and one of its box/packaging. This helps with identification and receiving verification.',
  },

  // ── Notifications ─────────────────────────────────────────

  'notifications.sound': {
    title: 'Sound Alerts',
    body: 'Enable sound alerts to hear a chime when new notifications arrive. You can enable or disable sounds for each notification type individually in Settings.',
  },

  // ── Dashboard ─────────────────────────────────────────────

  'dashboard.daily-report': {
    title: 'Daily Report',
    body: 'The daily report shows live, real-time data about today\'s activity — pending approvals, expected deliveries, and overdue items. It always reflects the current state, no date selection needed.',
  },

  // ── General ───────────────────────────────────────────────

  'general.permissions': {
    title: 'Role Permissions',
    body: 'Your access level determines what you can see and do. Field workers manage their own orders. Office staff handle PO management and receiving. Managers can approve orders and set costs.',
  },
};

export default helpContent;
