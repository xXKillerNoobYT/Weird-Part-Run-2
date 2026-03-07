/**
 * Local SQLite Database Manager
 *
 * Provides a unified interface for local database access on both
 * Capacitor (mobile) and browser (dev/testing) environments.
 *
 * On Capacitor: uses @capacitor-community/sqlite for native SQLite
 * On browser: operations are no-ops or throw (browser uses HTTP API)
 *
 * All services and repos access the DB through this module.
 */

import { isCapacitor } from '../lib/environment';

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

  if (!isCapacitor()) {
    throw new Error(
      'Local database is only available in Capacitor mode. ' +
      'Browser mode should use the HTTP API client.'
    );
  }

  _db = await createCapacitorDb();
  return _db;
}

/**
 * Initialize the database and run migrations.
 * Called during app startup in Capacitor mode.
 */
export async function initLocalDb(): Promise<void> {
  const db = await getDb();
  await runMigrations(db);
}

// ── Capacitor SQLite Implementation ────────────────────────────────

async function createCapacitorDb(): Promise<LocalDb> {
  const { CapacitorSQLite, SQLiteConnection } = await import(
    '@capacitor-community/sqlite'
  );

  const sqlite = new SQLiteConnection(CapacitorSQLite);
  const conn = await sqlite.createConnection(
    'wiredpart',   // database name
    false,         // encrypted
    'no-encryption',
    1,             // version
    false,         // readonly
  );
  await conn.open();

  return {
    async query(sql: string, params: any[] = []): Promise<QueryResult> {
      const result = await conn.query(sql, params);
      return { values: result.values || [] };
    },

    async run(sql: string, params: any[] = []): Promise<RunResult> {
      const result = await conn.run(sql, params);
      return {
        changes: {
          changes: result.changes?.changes ?? 0,
          lastId: result.changes?.lastId ?? 0,
        },
      };
    },

    async execute(sql: string): Promise<void> {
      await conn.execute(sql);
    },

    async close(): Promise<void> {
      await sqlite.closeConnection('wiredpart', false);
      _db = null;
    },
  };
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
      await db.execute(migration.sql);
      await db.run(
        'INSERT INTO _migrations (name) VALUES (?)',
        [migration.name],
      );
    }
  }
}
