/**
 * Shared helpers for report services.
 *
 * Internal utilities — not exported from the public barrel.
 */

import { getDb } from '../../db';

/** Run a SELECT query, returning [] if the table doesn't exist yet. */
export async function safeSelect<T = Record<string, any>>(
  sql: string,
  params: any[] = [],
): Promise<T[]> {
  const db = await getDb();
  try {
    const result = await db.query(sql, params);
    return (result.values ?? []) as T[];
  } catch {
    return [];
  }
}

/** Run a scalar query returning a single numeric value, 0 on failure. */
export async function safeScalar(sql: string, params: any[] = []): Promise<number> {
  const db = await getDb();
  try {
    const result = await db.query(sql, params);
    const row = result.values?.[0];
    if (!row) return 0;
    const val = Object.values(row)[0];
    return typeof val === 'number' ? val : 0;
  } catch {
    return 0;
  }
}

/**
 * Compute regular vs overtime for a set of labor entries grouped by employee+date.
 * Rule: >8 hours in a single day = overtime for that employee.
 * Returns entries with recalculated regular_hours / overtime_hours.
 */
export function computeOvertimeForEntries<T extends { user_id?: number; employee_id?: number; date: string; total_hours: number }>(
  entries: T[],
): (T & { regular_hours: number; overtime_hours: number })[] {
  // Group by employee+date
  const dayMap = new Map<string, T[]>();
  for (const e of entries) {
    const empId = (e as any).user_id ?? (e as any).employee_id ?? 0;
    const key = `${empId}|${e.date}`;
    const arr = dayMap.get(key) ?? [];
    arr.push(e);
    dayMap.set(key, arr);
  }

  const result: (T & { regular_hours: number; overtime_hours: number })[] = [];

  for (const group of Array.from(dayMap.values())) {
    const dayTotal = group.reduce((s, e) => s + e.total_hours, 0);
    const overtimeTotal = Math.max(0, dayTotal - 8);
    const regularTotal = dayTotal - overtimeTotal;

    // Distribute proportionally across entries
    for (const e of group) {
      const pct = dayTotal > 0 ? e.total_hours / dayTotal : 0;
      result.push({
        ...e,
        regular_hours: Math.round(regularTotal * pct * 100) / 100,
        overtime_hours: Math.round(overtimeTotal * pct * 100) / 100,
      });
    }
  }

  return result;
}

/** Convert an array of objects to CSV text */
export function toCsv(rows: Record<string, any>[]): string {
  if (rows.length === 0) return '';
  const headers = Object.keys(rows[0]);
  const lines = [
    headers.join(','),
    ...rows.map(row =>
      headers.map(h => {
        const val = row[h];
        if (val == null) return '';
        const str = String(val);
        // Escape fields containing commas, quotes, or newlines
        if (str.includes(',') || str.includes('"') || str.includes('\n')) {
          return `"${str.replace(/"/g, '""')}"`;
        }
        return str;
      }).join(','),
    ),
  ];
  return lines.join('\n');
}
