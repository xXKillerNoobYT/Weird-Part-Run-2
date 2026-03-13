/**
 * Base Repository — generic CRUD for local SQLite tables.
 *
 * Every repo extends this with table-specific queries.
 * All writes go through trackChange() for sync logging.
 */

import { getDb, type RunResult } from '../db';
import { trackChange } from '../change-tracker';

export class BaseRepo {
  protected tableName: string;
  protected primaryKey: string;

  constructor(tableName: string, primaryKey: string = 'id') {
    this.tableName = tableName;
    this.primaryKey = primaryKey;
  }

  /** Get a single record by primary key */
  async getById(id: number): Promise<Record<string, any> | null> {
    const db = await getDb();
    const result = await db.query(
      `SELECT * FROM ${this.tableName} WHERE ${this.primaryKey} = ?`,
      [id],
    );
    return result.values[0] ?? null;
  }

  /** Get all records matching optional WHERE clause */
  async findAll(
    where?: string,
    params?: any[],
    orderBy?: string,
    limit?: number,
    offset?: number,
  ): Promise<Record<string, any>[]> {
    const db = await getDb();
    let sql = `SELECT * FROM ${this.tableName}`;
    if (where) sql += ` WHERE ${where}`;
    if (orderBy) sql += ` ORDER BY ${orderBy}`;
    if (limit) sql += ` LIMIT ${limit}`;
    if (offset) sql += ` OFFSET ${offset}`;
    const result = await db.query(sql, params ?? []);
    return result.values;
  }

  /** Count records matching optional WHERE clause */
  async count(where?: string, params?: any[]): Promise<number> {
    const db = await getDb();
    let sql = `SELECT COUNT(*) as cnt FROM ${this.tableName}`;
    if (where) sql += ` WHERE ${where}`;
    const result = await db.query(sql, params ?? []);
    return result.values[0]?.cnt ?? 0;
  }

  /** Insert a record and track the change for sync */
  async insert(
    data: Record<string, any>,
    track = true,
  ): Promise<number> {
    const db = await getDb();
    const keys = Object.keys(data);
    const placeholders = keys.map(() => '?').join(', ');
    const values = keys.map((k) => data[k]);

    const result = await db.run(
      `INSERT INTO ${this.tableName} (${keys.join(', ')}) VALUES (${placeholders})`,
      values,
    );

    const newId = result.changes.lastId;

    if (track) {
      await trackChange(this.tableName, newId, 'INSERT', data);
    }

    return newId;
  }

  /** Update a record by primary key and track the change */
  async update(
    id: number,
    data: Record<string, any>,
    track = true,
  ): Promise<boolean> {
    const db = await getDb();
    const keys = Object.keys(data);
    if (keys.length === 0) return false;

    const setClauses = keys.map((k) => `${k} = ?`).join(', ');
    const values = [...keys.map((k) => data[k]), id];

    // Fetch old values for conflict resolution
    let oldValues: Record<string, any> | undefined;
    if (track) {
      const existing = await this.getById(id);
      if (existing) {
        oldValues = {};
        for (const key of keys) {
          oldValues[key] = existing[key];
        }
      }
    }

    const result = await db.run(
      `UPDATE ${this.tableName} SET ${setClauses} WHERE ${this.primaryKey} = ?`,
      values,
    );

    if (result.changes.changes > 0 && track) {
      await trackChange(this.tableName, id, 'UPDATE', data, oldValues);
    }

    return result.changes.changes > 0;
  }

  /** Delete a record and track the change */
  async delete(id: number, track = true): Promise<boolean> {
    const db = await getDb();

    let oldValues: Record<string, any> | undefined;
    if (track) {
      const existing = await this.getById(id);
      if (existing) oldValues = existing;
    }

    const result = await db.run(
      `DELETE FROM ${this.tableName} WHERE ${this.primaryKey} = ?`,
      [id],
    );

    if (result.changes.changes > 0 && track) {
      await trackChange(this.tableName, id, 'DELETE', undefined, oldValues);
    }

    return result.changes.changes > 0;
  }

  /** Run a raw query (for complex joins) */
  async rawQuery(sql: string, params?: any[]): Promise<Record<string, any>[]> {
    const db = await getDb();
    const result = await db.query(sql, params ?? []);
    return result.values;
  }

  /** Run a raw write (for complex updates) */
  async rawRun(sql: string, params?: any[]): Promise<RunResult> {
    const db = await getDb();
    return db.run(sql, params ?? []);
  }
}
