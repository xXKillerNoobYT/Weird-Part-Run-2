/**
 * Local Costs Service — cost tracking, margins, spending analytics, and budget alerts.
 *
 * Mirrors backend cost-tracking functionality (Phase 7D) for offline use.
 * Supports: company settings, cost layers, margin management, spending dashboard,
 * job cost rollup, price variance, budget alerts, and daily report.
 *
 * Source tables: migrations 001_foundation, 010_costs_receiving, plus
 * parts, stock, stock_movements, purchase_orders, purchase_order_lines,
 * receiving_session_items, suppliers, jobs, labor_entries, part_categories.
 */

import { getDb } from '../db';

import type {
  BudgetAlert,
  CategorySpend,
  CompanySetting,
  CostHistoryPoint,
  CostLayer,
  DailyReportActivity,
  DailyReportData,
  DailyReportDelivery,
  DailyReportPendingActions,
  JobCostRollup,
  JobSpend,
  PartCostSummary,
  PriceVarianceItem,
  SpendingSummary,
  SpendingTrendPoint,
  SupplierSpend,
} from '../../lib/types';

// ── Helpers ─────────────────────────────────────────────────────────

interface DateRangeParams {
  date_from?: string;
  date_to?: string;
}

/** Build a WHERE clause fragment for date-range filtering. */
function dateRangeWhere(
  dateCol: string,
  params?: DateRangeParams,
): { where: string; values: any[] } {
  const clauses: string[] = [];
  const values: any[] = [];
  if (params?.date_from) {
    clauses.push(`${dateCol} >= ?`);
    values.push(params.date_from);
  }
  if (params?.date_to) {
    clauses.push(`${dateCol} <= ?`);
    values.push(params.date_to);
  }
  return { where: clauses.length ? clauses.join(' AND ') : '1=1', values };
}

/** Read a single cost-category setting, returning its value or a fallback. */
async function readSetting(key: string, fallback: string): Promise<string> {
  const db = await getDb();
  const result = await db.query(
    `SELECT setting_value FROM settings WHERE setting_key = ? AND category = 'costs'`,
    [key],
  );
  return (result.values[0]?.setting_value as string) ?? fallback;
}

// ═══════════════════════════════════════════════════════════════════
// COMPANY COST SETTINGS
// ═══════════════════════════════════════════════════════════════════

/** Get all company cost settings. */
export async function getCompanySettings(): Promise<CompanySetting[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT s.setting_key, s.setting_value, s.updated_by, s.updated_at,
       u.display_name as updated_by_name
     FROM settings s
     LEFT JOIN users u ON u.id = s.updated_by
     WHERE s.category = 'costs'
     ORDER BY s.setting_key`,
  );
  return result.values as CompanySetting[];
}

/** Upsert a company cost setting. */
export async function updateCompanySetting(
  key: string,
  settingValue: string,
): Promise<CompanySetting> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Upsert via INSERT OR REPLACE
  await db.run(
    `INSERT INTO settings (setting_key, setting_value, category, updated_at)
     VALUES (?, ?, 'costs', ?)
     ON CONFLICT(setting_key) DO UPDATE SET
       setting_value = excluded.setting_value,
       updated_at = excluded.updated_at`,
    [key, settingValue, now],
  );

  // Return the updated row
  const result = await db.query(
    `SELECT s.setting_key, s.setting_value, s.updated_by, s.updated_at,
       u.display_name as updated_by_name
     FROM settings s
     LEFT JOIN users u ON u.id = s.updated_by
     WHERE s.setting_key = ?`,
    [key],
  );
  return result.values[0] as CompanySetting;
}

// ═══════════════════════════════════════════════════════════════════
// PER-PART COST LAYERS & HISTORY
// ═══════════════════════════════════════════════════════════════════

/** Get active cost layers for a part (FIFO audit view). */
export async function getCostLayers(partId: number): Promise<CostLayer[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT s.id, s.part_id, s.unit_cost, s.qty as remaining_qty,
       s.qty as original_qty, s.created_at,
       NULL as purchase_date, NULL as po_line_id, NULL as po_number
     FROM stock s
     WHERE s.part_id = ? AND s.qty > 0
     ORDER BY s.created_at ASC`,
    [partId],
  );
  return result.values as CostLayer[];
}

/** Get cost history for sparkline charts (receiving events within N days). */
export async function getCostHistory(
  partId: number,
  days: number = 90,
): Promise<CostHistoryPoint[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT DATE(ri.created_at) as date,
       SUM(ri.qty_received * ri.unit_cost) / SUM(ri.qty_received) as weighted_avg_cost,
       SUM(ri.qty_received) as total_qty
     FROM receiving_session_items ri
     WHERE ri.part_id = ?
       AND ri.deleted_at IS NULL
       AND ri.created_at >= DATE('now', '-' || ? || ' days')
     GROUP BY DATE(ri.created_at)
     ORDER BY date ASC`,
    [partId, days],
  );
  return result.values as CostHistoryPoint[];
}

/** Consolidated cost summary for a single part. */
export async function getPartCostSummary(partId: number): Promise<PartCostSummary> {
  const db = await getDb();

  // Weighted average cost from stock layers
  const layerResult = await db.query(
    `SELECT SUM(qty) as total_qty,
       CASE WHEN SUM(qty) > 0
         THEN SUM(qty * unit_cost) / SUM(qty)
         ELSE 0 END as weighted_avg_cost,
       COUNT(*) as active_layers,
       MAX(created_at) as cost_last_updated
     FROM stock
     WHERE part_id = ? AND qty > 0`,
    [partId],
  );
  const layer = layerResult.values[0] ?? {};

  // Part margin info
  const partResult = await db.query(
    `SELECT custom_margin, sell_price FROM parts WHERE id = ?`,
    [partId],
  );
  const part = partResult.values[0] ?? {};

  // Default margin from settings
  const defaultMargin = parseFloat(await readSetting('default_margin', '30'));
  const effectiveMargin = part.custom_margin ?? defaultMargin;
  const avgCost = layer.weighted_avg_cost ?? 0;
  const calcSellPrice = avgCost * (1 + effectiveMargin / 100);

  return {
    part_id: partId,
    weighted_avg_cost: avgCost,
    custom_margin_percent: part.custom_margin ?? null,
    effective_margin_percent: effectiveMargin,
    calculated_sell_price: calcSellPrice,
    cost_last_updated: layer.cost_last_updated ?? null,
    active_layers: layer.active_layers ?? 0,
  };
}

// ═══════════════════════════════════════════════════════════════════
// MARGIN MANAGEMENT
// ═══════════════════════════════════════════════════════════════════

/** Set a custom margin override on a part. */
export async function setCustomMargin(
  partId: number,
  marginPercent: number,
): Promise<PartCostSummary> {
  const db = await getDb();
  await db.run(
    `UPDATE parts SET custom_margin = ?,
       sell_price = unit_cost * (1 + ? / 100.0),
       updated_at = ?
     WHERE id = ?`,
    [marginPercent, marginPercent, new Date().toISOString(), partId],
  );
  return getPartCostSummary(partId);
}

/** Remove custom margin -- revert to company default. */
export async function clearCustomMargin(partId: number): Promise<PartCostSummary> {
  const db = await getDb();
  const defaultMargin = parseFloat(await readSetting('default_margin', '30'));
  await db.run(
    `UPDATE parts SET custom_margin = NULL,
       sell_price = unit_cost * (1 + ? / 100.0),
       updated_at = ?
     WHERE id = ?`,
    [defaultMargin, new Date().toISOString(), partId],
  );
  return getPartCostSummary(partId);
}

/** Reset ALL parts to company default margin. */
export async function enforceDefaultMargin(): Promise<{
  cleared_count: number;
  message: string;
}> {
  const db = await getDb();
  const defaultMargin = parseFloat(await readSetting('default_margin', '30'));
  const now = new Date().toISOString();

  // Count how many have custom margins
  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM parts WHERE custom_margin IS NOT NULL AND deleted_at IS NULL`,
  );
  const clearedCount = countResult.values[0]?.cnt ?? 0;

  // Clear all custom margins, recalculate sell prices
  await db.run(
    `UPDATE parts SET
       custom_margin = NULL,
       sell_price = unit_cost * (1 + ? / 100.0),
       updated_at = ?
     WHERE deleted_at IS NULL`,
    [defaultMargin, now],
  );

  return {
    cleared_count: clearedCount,
    message: `Cleared ${clearedCount} custom margin(s). All parts now use the default ${defaultMargin}% margin.`,
  };
}

// ═══════════════════════════════════════════════════════════════════
// SPENDING DASHBOARD
// ═══════════════════════════════════════════════════════════════════

/** Top-level spending KPIs. */
export async function getSpendingSummary(
  params?: DateRangeParams,
): Promise<SpendingSummary> {
  const db = await getDb();
  const { where, values } = dateRangeWhere('ri.created_at', params);

  const result = await db.query(
    `SELECT
       COALESCE(SUM(ri.qty_received * ri.unit_cost), 0) as total_spend,
       COUNT(DISTINCT ri.po_id) as order_count,
       COUNT(DISTINCT po.supplier_id) as active_suppliers
     FROM receiving_session_items ri
     JOIN purchase_orders po ON po.id = ri.po_id
     WHERE ri.deleted_at IS NULL AND ${where}`,
    values,
  );

  const row = result.values[0] ?? {};
  const totalSpend = row.total_spend ?? 0;
  const orderCount = row.order_count ?? 0;

  return {
    total_spend: totalSpend,
    order_count: orderCount,
    avg_order_size: orderCount > 0 ? totalSpend / orderCount : 0,
    active_suppliers: row.active_suppliers ?? 0,
  };
}

/** Spending breakdown by supplier. */
export async function getSpendingBySupplier(
  params?: DateRangeParams,
): Promise<SupplierSpend[]> {
  const db = await getDb();
  const { where, values } = dateRangeWhere('ri.created_at', params);

  // First get total for pct_of_total calculation
  const totalResult = await db.query(
    `SELECT COALESCE(SUM(ri.qty_received * ri.unit_cost), 0) as grand_total
     FROM receiving_session_items ri
     WHERE ri.deleted_at IS NULL AND ${where}`,
    values,
  );
  const grandTotal = totalResult.values[0]?.grand_total ?? 0;

  const result = await db.query(
    `SELECT
       po.supplier_id,
       s.name as supplier_name,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       COUNT(DISTINCT ri.po_id) as order_count
     FROM receiving_session_items ri
     JOIN purchase_orders po ON po.id = ri.po_id
     JOIN suppliers s ON s.id = po.supplier_id
     WHERE ri.deleted_at IS NULL AND ${where}
     GROUP BY po.supplier_id
     ORDER BY total_spend DESC`,
    values,
  );

  return (result.values as any[]).map((r) => ({
    supplier_id: r.supplier_id,
    supplier_name: r.supplier_name,
    total_spend: r.total_spend,
    order_count: r.order_count,
    pct_of_total: grandTotal > 0 ? (r.total_spend / grandTotal) * 100 : 0,
  }));
}

/** Spending breakdown by part category. */
export async function getSpendingByCategory(
  params?: DateRangeParams,
): Promise<CategorySpend[]> {
  const db = await getDb();
  const { where, values } = dateRangeWhere('ri.created_at', params);

  const result = await db.query(
    `SELECT
       p.category_id,
       COALESCE(pc.name, 'Uncategorized') as category_name,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       COUNT(DISTINCT ri.part_id) as item_count
     FROM receiving_session_items ri
     JOIN parts p ON p.id = ri.part_id
     LEFT JOIN part_categories pc ON pc.id = p.category_id
     WHERE ri.deleted_at IS NULL AND ${where}
     GROUP BY p.category_id
     ORDER BY total_spend DESC`,
    values,
  );

  return result.values as CategorySpend[];
}

/** Spending breakdown by job. */
export async function getSpendingByJob(
  params?: DateRangeParams,
): Promise<JobSpend[]> {
  const db = await getDb();
  const { where, values } = dateRangeWhere('ri.created_at', params);

  const result = await db.query(
    `SELECT
       po.job_id,
       j.job_name,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       j.budget_limit
     FROM receiving_session_items ri
     JOIN purchase_orders po ON po.id = ri.po_id
     LEFT JOIN jobs j ON j.id = po.job_id
     WHERE ri.deleted_at IS NULL AND po.job_id IS NOT NULL AND ${where}
     GROUP BY po.job_id
     ORDER BY total_spend DESC`,
    values,
  );

  return (result.values as any[]).map((r) => ({
    job_id: r.job_id,
    job_name: r.job_name,
    total_spend: r.total_spend,
    budget_limit: r.budget_limit,
    budget_pct:
      r.budget_limit && r.budget_limit > 0
        ? (r.total_spend / r.budget_limit) * 100
        : null,
  }));
}

/** Spending trend over time (monthly or weekly). */
export async function getSpendingTrend(
  params?: DateRangeParams & { group_by?: 'month' | 'week' },
): Promise<SpendingTrendPoint[]> {
  const db = await getDb();
  const { where, values } = dateRangeWhere('ri.created_at', params);

  // Default to monthly grouping
  const groupBy = params?.group_by ?? 'month';
  const fmt = groupBy === 'week' ? '%Y-W%W' : '%Y-%m';

  const result = await db.query(
    `SELECT
       strftime('${fmt}', ri.created_at) as period_label,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       COUNT(DISTINCT ri.po_id) as order_count
     FROM receiving_session_items ri
     WHERE ri.deleted_at IS NULL AND ${where}
     GROUP BY period_label
     ORDER BY period_label ASC`,
    values,
  );

  return result.values as SpendingTrendPoint[];
}

// ═══════════════════════════════════════════════════════════════════
// JOB COST ROLLUP & BUDGET
// ═══════════════════════════════════════════════════════════════════

/** Full cost rollup for a job (parts + labor). */
export async function getJobCostRollup(jobId: number): Promise<JobCostRollup> {
  const db = await getDb();

  // Job info
  const jobResult = await db.query(
    `SELECT id, job_name, budget_limit FROM jobs WHERE id = ?`,
    [jobId],
  );
  const job = jobResult.values[0] ?? {};

  // Labor cost from labor_entries
  const laborResult = await db.query(
    `SELECT
       COALESCE(SUM(hours), 0) as total_labor_hours,
       COALESCE(SUM(hours * pay_rate), 0) as total_labor_cost
     FROM labor_entries
     WHERE job_id = ? AND deleted_at IS NULL`,
    [jobId],
  );
  const labor = laborResult.values[0] ?? {};

  // Parts cost from stock_movements to this job
  const partsResult = await db.query(
    `SELECT COALESCE(SUM(sm.qty * sm.unit_cost), 0) as total_parts_cost
     FROM stock_movements sm
     WHERE sm.to_type = 'job' AND sm.to_id = ? AND sm.deleted_at IS NULL`,
    [jobId],
  );
  const parts = partsResult.values[0] ?? {};

  const totalLabor = labor.total_labor_cost ?? 0;
  const totalParts = parts.total_parts_cost ?? 0;
  const combined = totalLabor + totalParts;
  const budgetLimit = job.budget_limit ?? null;

  // Budget alert threshold from settings (default 80%)
  const alertThreshold = parseFloat(await readSetting('budget_alert_percent', '80'));

  return {
    job_id: jobId,
    job_name: job.job_name ?? '',
    total_parts_cost: totalParts,
    total_labor_cost: totalLabor,
    total_labor_hours: labor.total_labor_hours ?? 0,
    combined_total: combined,
    budget_limit: budgetLimit,
    budget_remaining: budgetLimit != null ? budgetLimit - combined : null,
    budget_pct: budgetLimit != null && budgetLimit > 0 ? (combined / budgetLimit) * 100 : null,
    budget_alert_percent: alertThreshold,
  };
}

/** Quick budget status for a job. */
export async function getJobBudgetStatus(jobId: number): Promise<{
  job_id: number;
  budget_limit: number | null;
  current_spend: number;
  budget_pct: number | null;
  alert_level: string | null;
}> {
  const db = await getDb();

  const jobResult = await db.query(
    `SELECT budget_limit FROM jobs WHERE id = ?`,
    [jobId],
  );
  const budgetLimit = jobResult.values[0]?.budget_limit ?? null;

  // Total spend = parts cost + labor cost
  const partsResult = await db.query(
    `SELECT COALESCE(SUM(sm.qty * sm.unit_cost), 0) as cost
     FROM stock_movements sm
     WHERE sm.to_type = 'job' AND sm.to_id = ? AND sm.deleted_at IS NULL`,
    [jobId],
  );
  const laborResult = await db.query(
    `SELECT COALESCE(SUM(hours * pay_rate), 0) as cost
     FROM labor_entries
     WHERE job_id = ? AND deleted_at IS NULL`,
    [jobId],
  );
  const currentSpend =
    (partsResult.values[0]?.cost ?? 0) + (laborResult.values[0]?.cost ?? 0);

  let budgetPct: number | null = null;
  let alertLevel: string | null = null;

  if (budgetLimit != null && budgetLimit > 0) {
    budgetPct = (currentSpend / budgetLimit) * 100;
    if (budgetPct >= 100) {
      alertLevel = 'critical';
    } else if (budgetPct >= 80) {
      alertLevel = 'warning';
    } else {
      alertLevel = 'ok';
    }
  }

  return {
    job_id: jobId,
    budget_limit: budgetLimit,
    current_spend: currentSpend,
    budget_pct: budgetPct,
    alert_level: alertLevel,
  };
}

// ═══════════════════════════════════════════════════════════════════
// PRICE VARIANCE & BUDGET ALERTS
// ═══════════════════════════════════════════════════════════════════

/** Price variance report: received cost vs PO quoted cost. */
export async function getPriceVarianceReport(
  params?: DateRangeParams,
): Promise<PriceVarianceItem[]> {
  const db = await getDb();
  const { where, values } = dateRangeWhere('ri.created_at', params);

  const result = await db.query(
    `SELECT
       ri.part_id,
       p.description as part_name,
       s.name as supplier_name,
       po.po_number,
       pol.unit_cost as quoted_price,
       ri.unit_cost as actual_price,
       (ri.unit_cost - pol.unit_cost) as variance_amount,
       CASE WHEN pol.unit_cost > 0
         THEN ((ri.unit_cost - pol.unit_cost) / pol.unit_cost) * 100
         ELSE 0 END as variance_pct
     FROM receiving_session_items ri
     JOIN purchase_order_lines pol ON pol.po_id = ri.po_id AND pol.part_id = ri.part_id
     JOIN purchase_orders po ON po.id = ri.po_id
     JOIN parts p ON p.id = ri.part_id
     LEFT JOIN suppliers s ON s.id = po.supplier_id
     WHERE ri.deleted_at IS NULL
       AND ri.unit_cost IS NOT NULL
       AND pol.unit_cost IS NOT NULL
       AND ABS(ri.unit_cost - pol.unit_cost) > 0.001
       AND ${where}
     ORDER BY ABS(variance_pct) DESC`,
    values,
  );

  return (result.values as any[]).map((r) => ({
    ...r,
    variance_level:
      Math.abs(r.variance_pct) >= 20
        ? 'danger'
        : Math.abs(r.variance_pct) >= 5
          ? 'warning'
          : 'ok',
  })) as PriceVarianceItem[];
}

/** Find jobs where spending exceeds budget thresholds. */
export async function getBudgetAlerts(): Promise<BudgetAlert[]> {
  const db = await getDb();

  // Get all jobs with a budget
  const jobsResult = await db.query(
    `SELECT id, job_name, budget_limit
     FROM jobs
     WHERE budget_limit IS NOT NULL AND budget_limit > 0
       AND deleted_at IS NULL AND status != 'closed'`,
  );

  const alerts: BudgetAlert[] = [];
  for (const job of jobsResult.values as any[]) {
    // Parts cost
    const partsResult = await db.query(
      `SELECT COALESCE(SUM(sm.qty * sm.unit_cost), 0) as cost
       FROM stock_movements sm
       WHERE sm.to_type = 'job' AND sm.to_id = ? AND sm.deleted_at IS NULL`,
      [job.id],
    );
    // Labor cost
    const laborResult = await db.query(
      `SELECT COALESCE(SUM(hours * pay_rate), 0) as cost
       FROM labor_entries
       WHERE job_id = ? AND deleted_at IS NULL`,
      [job.id],
    );

    const currentSpend =
      (partsResult.values[0]?.cost ?? 0) + (laborResult.values[0]?.cost ?? 0);
    const pctUsed = (currentSpend / job.budget_limit) * 100;

    if (pctUsed >= 80) {
      alerts.push({
        job_id: job.id,
        job_name: job.job_name,
        budget_limit: job.budget_limit,
        current_spend: currentSpend,
        pct_used: pctUsed,
        alert_level: pctUsed >= 100 ? 'danger' : 'warning',
      });
    }
  }

  return alerts.sort((a, b) => b.pct_used - a.pct_used);
}

// ═══════════════════════════════════════════════════════════════════
// DAILY REPORT
// ═══════════════════════════════════════════════════════════════════

/** Live daily report: pending actions, deliveries, activity, and budget alerts. */
export async function getDailyReport(): Promise<DailyReportData> {
  const db = await getDb();
  const today = new Date().toISOString().slice(0, 10);

  // Pending actions
  const jposResult = await db.query(
    `SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE status = 'draft' AND deleted_at IS NULL`,
  );
  const posResult = await db.query(
    `SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE status = 'approved' AND deleted_at IS NULL`,
  );
  const returnsResult = await db.query(
    `SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE status = 'return_pending' AND deleted_at IS NULL`,
  );
  const overdueDeliveriesResult = await db.query(
    `SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE expected_delivery < ? AND status IN ('submitted','acknowledged')
       AND deleted_at IS NULL`,
    [today],
  );

  const pendingActions: DailyReportPendingActions = {
    jpos_awaiting_approval: jposResult.values[0]?.cnt ?? 0,
    pos_to_submit: posResult.values[0]?.cnt ?? 0,
    returns_to_sort: returnsResult.values[0]?.cnt ?? 0,
    overdue_deliveries: overdueDeliveriesResult.values[0]?.cnt ?? 0,
  };

  // Expected deliveries (this week)
  const weekEnd = new Date();
  weekEnd.setDate(weekEnd.getDate() + 7);
  const weekEndStr = weekEnd.toISOString().slice(0, 10);

  const deliveriesResult = await db.query(
    `SELECT po.id as po_id, po.po_number,
       s.name as supplier_name,
       po.expected_delivery,
       (SELECT COUNT(*) FROM purchase_order_lines pol WHERE pol.po_id = po.id) as line_count,
       CASE WHEN po.expected_delivery < ? THEN 1 ELSE 0 END as is_overdue
     FROM purchase_orders po
     LEFT JOIN suppliers s ON s.id = po.supplier_id
     WHERE po.expected_delivery IS NOT NULL
       AND po.expected_delivery <= ?
       AND po.status IN ('submitted','acknowledged')
       AND po.deleted_at IS NULL
     ORDER BY po.expected_delivery ASC`,
    [today, weekEndStr],
  );
  const allDeliveries = deliveriesResult.values as DailyReportDelivery[];
  const expectedDeliveries = allDeliveries.filter((d) => !d.is_overdue);
  const overdueItems = allDeliveries.filter((d) => d.is_overdue);

  // Today's activity
  const ordersCreatedResult = await db.query(
    `SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE DATE(created_at) = ? AND deleted_at IS NULL`,
    [today],
  );
  const itemsReceivedResult = await db.query(
    `SELECT COUNT(*) as cnt FROM receiving_session_items
     WHERE DATE(created_at) = ? AND deleted_at IS NULL AND qty_received > 0`,
    [today],
  );
  const returnsProcessedResult = await db.query(
    `SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE DATE(updated_at) = ? AND status = 'returned' AND deleted_at IS NULL`,
    [today],
  );

  const todaysActivity: DailyReportActivity = {
    orders_created: ordersCreatedResult.values[0]?.cnt ?? 0,
    items_received: itemsReceivedResult.values[0]?.cnt ?? 0,
    returns_processed: returnsProcessedResult.values[0]?.cnt ?? 0,
  };

  // Budget alerts
  const budgetAlerts = await getBudgetAlerts();

  return {
    pending_actions: pendingActions,
    expected_deliveries: expectedDeliveries,
    overdue_items: overdueItems,
    todays_activity: todaysActivity,
    budget_alerts: budgetAlerts,
  };
}
