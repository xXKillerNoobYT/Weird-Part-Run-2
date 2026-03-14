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
 * Migration 007: Chat & Q&A (channels, messages, Q&A threads, RFIs)
 * Migration 008: Soft Delete + Sync Infrastructure (deleted_at, conflict log, vector clocks)
 * Migration 009: People Full (certifications, wages, notes, skills, teams)
 * Migration 010: Costs & Receiving (billing periods, receiving sessions)
 * Migration 011: Reports & PTO (annotations, share tokens, templates, PTO tracking)
 * Migration 012: Warehouse & Attachments (trailers, order attachments)
 * Migration 013: Tools & Supplier Extras (depreciation, calibration, supplier portal)
 * Migration 014: Contacts, Costs & Profiles (entity contacts, job linking, cost layers, company profiles)
 * Migration 015: Job Team & Suppliers
 * Migration 016: Companions & Alternatives
 * Migration 017: Permission Backfill (use_chat, view_customers, view_contractors, manage_remote_sync, etc.)
 */

import { migration as m001 } from './001_foundation';
import { migration as m002 } from './002_parts_inventory';
import { migration as m003 } from './003_jobs_labor';
import { migration as m004 } from './004_notebooks';
import { migration as m005 } from './005_orders';
import { migration as m006 } from './006_fleet_tools_scheduling';
import { migration as m007 } from './007_chat';
import { migration as m008 } from './008_soft_delete_and_sync';
import { migration as m009 } from './009_people_full';
import { migration as m010 } from './010_costs_receiving';
import { migration as m011 } from './011_reports_pto';
import { migration as m012 } from './012_warehouse_attachments';
import { migration as m013 } from './013_tools_supplier_extras';
import { migration as m014 } from './014_contacts_costs_profiles';
import { migration as m015 } from './015_job_team_suppliers';
import { migration as m016 } from './016_companions_alternatives';
import { migration as m017 } from './017_permission_backfill';

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
  m007,
  m008,
  m009,
  m010,
  m011,
  m012,
  m013,
  m014,
  m015,
  m016,
  m017,
];
