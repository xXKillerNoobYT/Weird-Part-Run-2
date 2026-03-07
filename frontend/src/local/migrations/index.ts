/**
 * Local SQLite Migrations — index
 *
 * Consolidated from 29 backend Python migrations into 7 logical groups.
 * The mobile DB starts fresh (no incremental ALTER TABLE steps needed).
 * Migrations run in order on first app launch and on updates.
 *
 * Migration 000: Change log (sync tracking)
 * Migration 001: Foundation (users, hats, permissions, settings, notifications)
 * Migration 002: Parts & Inventory (hierarchy, brands, suppliers, stock, movements)
 * Migration 003: Jobs & Labor (jobs, labor entries, clock-out, daily reports)
 * Migration 004: Notebooks (templates, sections, entries, tasks)
 * Migration 005: Orders (JPOs, POs, returns, staging, special items)
 * Migration 006: Fleet, Tools & Scheduling (vehicles, tools, kits, dispatch)
 */

import { migration as m001 } from './001_foundation';
import { migration as m002 } from './002_parts_inventory';
import { migration as m003 } from './003_jobs_labor';
import { migration as m004 } from './004_notebooks';
import { migration as m005 } from './005_orders';
import { migration as m006 } from './006_fleet_tools_scheduling';

export interface Migration {
  name: string;
  sql: string;
}

export const migrations: Migration[] = [
  // 000: Change log for sync (must be first — other migrations may trigger tracking)
  {
    name: '000_change_log',
    sql: `
      CREATE TABLE IF NOT EXISTS _change_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
        changed_fields TEXT,
        old_values TEXT,
        timestamp TEXT NOT NULL DEFAULT (datetime('now')),
        synced INTEGER NOT NULL DEFAULT 0,
        sync_batch_id TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_change_log_unsynced ON _change_log(synced, timestamp);
      CREATE INDEX IF NOT EXISTS idx_change_log_table ON _change_log(table_name, record_id);
    `,
  },
  m001,
  m002,
  m003,
  m004,
  m005,
  m006,
];
