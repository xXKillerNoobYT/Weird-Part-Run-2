/**
 * Local SQLite Database Manager
 *
 * Provides a unified interface for local database access:
 * - **Tauri** (desktop + mobile): uses @tauri-apps/plugin-sql
 * - **Browser** (dev/testing): throws — browser uses HTTP API
 *
 * All local services and repos access the DB through this module.
 */

import { isTauri } from '../lib/environment';
import { getDbConnectionString } from './db-config';

// ── Types ──────────────────────────────────────────────────────────

export interface QueryResult {
  values: Record<string, any>[];
}

export interface RunResult {
  changes: { changes: number; lastId: number };
}

export interface LocalDb {
  query(sql: string, params?: any[]): Promise<QueryResult>;
  run(sql: string, params?: any[]): Promise<RunResult>;
  /** Execute raw SQL (DDL or multi-statement). Handles splitting for Tauri. */
  execute(sql: string): Promise<void>;
  close(): Promise<void>;
}

// ── Singleton ──────────────────────────────────────────────────────

let _db: LocalDb | null = null;

/**
 * Get the local SQLite database connection.
 * Creates and initializes the connection on first call.
 */
export async function getDb(): Promise<LocalDb> {
  if (_db) return _db;

  if (!isTauri()) {
    throw new Error(
      'Local database is only available in Tauri native mode. ' +
      'Browser mode should use the HTTP API client.'
    );
  }

  _db = await createTauriDb();
  return _db;
}

/**
 * Initialize the database and run migrations.
 * Called during app startup in native mode.
 */
export async function initLocalDb(): Promise<void> {
  const db = await getDb();
  await runMigrations(db);
}

// ── Tauri SQL Plugin Implementation ────────────────────────────────

/**
 * Creates a LocalDb backed by Tauri's SQL plugin (tauri-plugin-sql).
 *
 * Uses Tauri's SQL plugin API:
 * - Database.load() opens/creates the database
 * - db.select() for reads, db.execute() for writes
 * - Does NOT support multi-statement SQL — we split on semicolons
 * - Returns lastInsertId/rowsAffected instead of changes object
 */
async function createTauriDb(): Promise<LocalDb> {
  const Database = (await import('@tauri-apps/plugin-sql')).default;

  // Resolve DB path from config: private mode → app data dir, public mode → shared dir
  const connectionString = await getDbConnectionString();
  console.log(`[db] Opening database: ${connectionString}`);
  const db = await Database.load(connectionString);

  return {
    async query(sql: string, params: any[] = []): Promise<QueryResult> {
      const rows = await db.select<Record<string, any>[]>(sql, params);
      return { values: rows };
    },

    async run(sql: string, params: any[] = []): Promise<RunResult> {
      const result = await db.execute(sql, params);
      return {
        changes: {
          changes: result.rowsAffected,
          lastId: result.lastInsertId ?? 0,
        },
      };
    },

    async execute(sql: string): Promise<void> {
      // Tauri's SQL plugin does NOT support multi-statement SQL.
      // Split on semicolons and execute each statement individually.
      const statements = splitSqlStatements(sql);
      for (const stmt of statements) {
        try {
          await db.execute(stmt, []);
        } catch (err: any) {
          // ALTER TABLE ADD COLUMN is not idempotent in SQLite (no IF NOT EXISTS).
          // If a migration partially fails, re-running it would hit "duplicate column"
          // errors on columns that were already added. Safely skip those.
          const msg = String(err?.message || err || '');
          if (
            /duplicate column name/i.test(msg) &&
            /ALTER\s+TABLE/i.test(stmt)
          ) {
            console.warn(`[db] Skipping duplicate column: ${stmt.slice(0, 80)}…`);
            continue;
          }
          throw err; // Re-throw all other errors
        }
      }
    },

    async close(): Promise<void> {
      await db.close();
      _db = null;
    },
  };
}

// ── SQL Statement Splitter ─────────────────────────────────────────

/**
 * Split a multi-statement SQL string into individual statements.
 * Handles quoted strings containing semicolons correctly.
 * Used by the Tauri backend which doesn't support multi-statement SQL.
 */
function splitSqlStatements(sql: string): string[] {
  const statements: string[] = [];
  let current = '';
  let inSingleQuote = false;
  let inDoubleQuote = false;
  let escaped = false;

  for (let i = 0; i < sql.length; i++) {
    const ch = sql[i];

    if (escaped) {
      current += ch;
      escaped = false;
      continue;
    }

    if (ch === '\\') {
      current += ch;
      escaped = true;
      continue;
    }

    if (ch === "'" && !inDoubleQuote) {
      // Handle '' escape in SQLite
      if (inSingleQuote && i + 1 < sql.length && sql[i + 1] === "'") {
        current += "''";
        i++;
        continue;
      }
      inSingleQuote = !inSingleQuote;
      current += ch;
      continue;
    }

    if (ch === '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      current += ch;
      continue;
    }

    if (ch === ';' && !inSingleQuote && !inDoubleQuote) {
      const trimmed = current.trim();
      if (trimmed.length > 0) {
        statements.push(trimmed);
      }
      current = '';
      continue;
    }

    current += ch;
  }

  // Handle last statement (no trailing semicolon)
  const trimmed = current.trim();
  if (trimmed.length > 0) {
    statements.push(trimmed);
  }

  return statements;
}

// ── Migration Runner ───────────────────────────────────────────────

async function runMigrations(db: LocalDb): Promise<void> {
  // Create migration tracking table
  await db.execute(`
    CREATE TABLE IF NOT EXISTS _migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);

  // Import migrations lazily
  const { migrations } = await import('./migrations');

  for (const migration of migrations) {
    const result = await db.query(
      'SELECT 1 FROM _migrations WHERE name = ?',
      [migration.name],
    );

    if (!result.values.length) {
      console.log(`[db] Running migration: ${migration.name}`);
      await db.execute(migration.sql);
      await db.run(
        'INSERT INTO _migrations (name) VALUES (?)',
        [migration.name],
      );
      console.log(`[db] Migration complete: ${migration.name}`);
    }
  }
}
