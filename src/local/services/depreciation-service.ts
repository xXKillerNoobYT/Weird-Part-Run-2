/**
 * Local Depreciation Service — tool depreciation schedule management.
 *
 * Calculates and stores annual depreciation entries for tools.
 * Supports straight-line, declining balance, and sum-of-years methods.
 *
 * Source tables: migration 013_tools_supplier_extras
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export type DepreciationMethod = 'straight_line' | 'declining_balance' | 'sum_of_years';

export interface DepreciationEntryCreate {
  tool_id: number;
  year_number: number;
  fiscal_year: string;
  beginning_value: number;
  depreciation_amount: number;
  accumulated: number;
  ending_value: number;
}

export interface DepreciationEntry {
  id: number;
  tool_id: number;
  year_number: number;
  fiscal_year: string;
  beginning_value: number;
  depreciation_amount: number;
  accumulated: number;
  ending_value: number;
  deleted_at: string | null;
  created_at: string;
}

export interface ToolDepreciationSummary {
  tool_id: number;
  tool_name: string;
  tool_code: string;
  purchase_price: number | null;
  depreciation_method: string | null;
  salvage_value: number;
  useful_life_years: number | null;
  current_book_value: number | null;
  total_depreciation: number;
  entries: DepreciationEntry[];
}

// ── Repos ──────────────────────────────────────────────────────────

const entryRepo = new BaseRepo('tool_depreciation_entries');

// ═══════════════════════════════════════════════════════════════════
// DEPRECIATION ENTRIES
// ═══════════════════════════════════════════════════════════════════

/** Create a depreciation entry */
export async function createEntry(data: DepreciationEntryCreate): Promise<DepreciationEntry> {
  const id = await entryRepo.insert({
    tool_id: data.tool_id,
    year_number: data.year_number,
    fiscal_year: data.fiscal_year,
    beginning_value: data.beginning_value,
    depreciation_amount: data.depreciation_amount,
    accumulated: data.accumulated,
    ending_value: data.ending_value,
    created_at: new Date().toISOString(),
  });
  return (await entryRepo.getById(id)) as DepreciationEntry;
}

/** Get depreciation schedule for a tool */
export async function getToolSchedule(toolId: number): Promise<DepreciationEntry[]> {
  return (await entryRepo.findAll(
    'tool_id = ? AND deleted_at IS NULL',
    [toolId],
    'year_number ASC',
  )) as DepreciationEntry[];
}

/** Get full depreciation summary for a tool */
export async function getToolDepreciationSummary(toolId: number): Promise<ToolDepreciationSummary | null> {
  const db = await getDb();

  const toolResult = await db.query(
    `SELECT id as tool_id, name as tool_name, tool_code,
       purchase_price, depreciation_method, salvage_value, useful_life_years
     FROM tools WHERE id = ?`,
    [toolId],
  );
  const tool = toolResult.values[0];
  if (!tool) return null;

  const entries = await getToolSchedule(toolId);
  const lastEntry = entries[entries.length - 1];

  return {
    tool_id: tool.tool_id as number,
    tool_name: tool.tool_name as string,
    tool_code: tool.tool_code as string,
    purchase_price: tool.purchase_price as number | null,
    depreciation_method: tool.depreciation_method as string | null,
    salvage_value: (tool.salvage_value as number) ?? 0,
    useful_life_years: tool.useful_life_years as number | null,
    current_book_value: lastEntry?.ending_value ?? tool.purchase_price as number | null,
    total_depreciation: lastEntry?.accumulated ?? 0,
    entries,
  };
}

/** Generate a full depreciation schedule for a tool (replaces existing entries) */
export async function generateSchedule(
  toolId: number,
  purchasePrice: number,
  salvageValue: number,
  usefulLifeYears: number,
  method: DepreciationMethod,
  startYear: number,
): Promise<DepreciationEntry[]> {
  const db = await getDb();

  // Soft-delete existing entries
  await db.run(
    `UPDATE tool_depreciation_entries SET deleted_at = datetime('now')
     WHERE tool_id = ? AND deleted_at IS NULL`,
    [toolId],
  );

  const depreciableBase = purchasePrice - salvageValue;
  const entries: DepreciationEntry[] = [];
  let accumulated = 0;

  for (let year = 1; year <= usefulLifeYears; year++) {
    const beginningValue = purchasePrice - accumulated;
    let amount: number;

    switch (method) {
      case 'straight_line':
        amount = depreciableBase / usefulLifeYears;
        break;
      case 'declining_balance': {
        const rate = (2 / usefulLifeYears); // Double declining
        amount = Math.min(beginningValue * rate, beginningValue - salvageValue);
        break;
      }
      case 'sum_of_years': {
        const sumYears = (usefulLifeYears * (usefulLifeYears + 1)) / 2;
        const fraction = (usefulLifeYears - year + 1) / sumYears;
        amount = depreciableBase * fraction;
        break;
      }
    }

    // Ensure we don't depreciate below salvage value
    amount = Math.max(0, Math.min(amount, beginningValue - salvageValue));
    amount = Math.round(amount * 100) / 100;
    accumulated += amount;

    const entry = await createEntry({
      tool_id: toolId,
      year_number: year,
      fiscal_year: String(startYear + year - 1),
      beginning_value: Math.round(beginningValue * 100) / 100,
      depreciation_amount: amount,
      accumulated: Math.round(accumulated * 100) / 100,
      ending_value: Math.round((beginningValue - amount) * 100) / 100,
    });
    entries.push(entry);
  }

  // Update tool with depreciation settings
  await db.run(
    `UPDATE tools SET depreciation_method = ?, salvage_value = ?,
       useful_life_years = ?, updated_at = datetime('now')
     WHERE id = ?`,
    [method, salvageValue, usefulLifeYears, toolId],
  );

  return entries;
}

/** Get entries for a specific fiscal year across all tools */
export async function getEntriesByFiscalYear(fiscalYear: string): Promise<(DepreciationEntry & { tool_name: string; tool_code: string })[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT tde.*, t.name as tool_name, t.tool_code
     FROM tool_depreciation_entries tde
     JOIN tools t ON t.id = tde.tool_id
     WHERE tde.fiscal_year = ? AND tde.deleted_at IS NULL
     ORDER BY t.tool_code ASC`,
    [fiscalYear],
  );
  return result.values as any[];
}
