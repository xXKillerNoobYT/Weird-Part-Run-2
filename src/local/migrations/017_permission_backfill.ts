/**
 * Migration 017: Permission Backfill
 *
 * Adds missing permission keys that were introduced after the initial seed:
 * - use_chat, ask_qa, send_rfi — needed for Chat module visibility
 * - view_customers, view_contractors — needed for People (contacts) module
 * - manage_remote_sync — needed for Remote Sync settings
 *
 * Uses INSERT OR IGNORE so it's safe to run on both new and existing databases.
 */

import type { Migration } from './index';

export const migration: Migration = {
  name: '017_permission_backfill',
  sql: `
    -- Admin hat: add all 6 missing permissions
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'use_chat' FROM hats WHERE name = 'Admin';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'ask_qa' FROM hats WHERE name = 'Admin';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'send_rfi' FROM hats WHERE name = 'Admin';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_customers' FROM hats WHERE name = 'Admin';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_contractors' FROM hats WHERE name = 'Admin';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'manage_remote_sync' FROM hats WHERE name = 'Admin';

    -- Manager hat: chat + contacts (no remote sync)
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'use_chat' FROM hats WHERE name = 'Manager';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_chat' FROM hats WHERE name = 'Manager';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'manage_chat' FROM hats WHERE name = 'Manager';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'ask_qa' FROM hats WHERE name = 'Manager';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'send_rfi' FROM hats WHERE name = 'Manager';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_customers' FROM hats WHERE name = 'Manager';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_contractors' FROM hats WHERE name = 'Manager';

    -- Office hat: chat (no manage/moderate) + contacts
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'use_chat' FROM hats WHERE name = 'Office';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_chat' FROM hats WHERE name = 'Office';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'ask_qa' FROM hats WHERE name = 'Office';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_customers' FROM hats WHERE name = 'Office';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_contractors' FROM hats WHERE name = 'Office';

    -- Lead hat: basic chat + view customers
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'use_chat' FROM hats WHERE name = 'Lead';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_chat' FROM hats WHERE name = 'Lead';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'ask_qa' FROM hats WHERE name = 'Lead';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_customers' FROM hats WHERE name = 'Lead';

    -- Worker hat: basic chat only
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'use_chat' FROM hats WHERE name = 'Worker';
    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
      SELECT id, 'view_chat' FROM hats WHERE name = 'Worker';
  `,
};
