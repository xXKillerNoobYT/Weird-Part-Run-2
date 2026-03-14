/**
 * Local Contacts Service — customers, general contractors, entity contacts,
 * directory search, job linking, CSV import, and dedupe/merge.
 *
 * Mirrors the HTTP API in `api/contacts.ts` for offline Tauri use.
 * Supports: customers, GCs, supplier contacts, entity contacts, job linking,
 * CSV import, and duplicate detection / merge.
 *
 * Source tables: migration 006_fleet_tools_scheduling (customers, general_contractors),
 *               migration 008_soft_delete_and_sync (deleted_at columns),
 *               entity_contacts, job_customers, job_general_contractors
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Repos ──────────────────────────────────────────────────────────

const customerRepo = new BaseRepo('customers');
const gcRepo = new BaseRepo('general_contractors');
const contactRepo = new BaseRepo('entity_contacts');
const jobCustomerRepo = new BaseRepo('job_customers');
const jobGCRepo = new BaseRepo('job_general_contractors');

// ── Shared Types ───────────────────────────────────────────────────

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
}

export interface CSVImportResult {
  created: number;
  skipped: number;
  errors: { row: number; error: string }[];
}

export interface DuplicatePair {
  a: { id: number; name: string; email?: string; phone?: string };
  b: { id: number; name: string; email?: string; phone?: string };
  similarity: number;
  match_type: string;
}

// ═══════════════════════════════════════════════════════════════════
// CUSTOMERS
// ═══════════════════════════════════════════════════════════════════

export interface CustomerListParams {
  search?: string;
  customer_type?: string;
  is_active?: boolean;
  page?: number;
  page_size?: number;
}

/** Paginated customer list with job/contact counts */
export async function getCustomers(
  params: CustomerListParams = {},
): Promise<PaginatedResult<any>> {
  const db = await getDb();
  const page = params.page ?? 1;
  const pageSize = params.page_size ?? 25;
  const conditions: string[] = ['c.deleted_at IS NULL'];
  const queryParams: any[] = [];

  if (params.search) {
    conditions.push('(c.name LIKE ? OR c.company_name LIKE ? OR c.email LIKE ?)');
    const term = `%${params.search}%`;
    queryParams.push(term, term, term);
  }
  if (params.customer_type) {
    conditions.push('c.customer_type = ?');
    queryParams.push(params.customer_type);
  }
  if (params.is_active !== undefined) {
    conditions.push('c.is_active = ?');
    queryParams.push(params.is_active ? 1 : 0);
  }

  const whereClause = conditions.join(' AND ');

  // Total count
  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM customers c WHERE ${whereClause}`,
    queryParams,
  );
  const total = countResult.values[0]?.cnt ?? 0;

  // Paginated items with subquery counts
  const items = await db.query(
    `SELECT c.*,
       (SELECT COUNT(*) FROM job_customers jc WHERE jc.customer_id = c.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'customer' AND ec.entity_id = c.id AND ec.deleted_at IS NULL) as contact_count
     FROM customers c
     WHERE ${whereClause}
     ORDER BY c.name ASC
     LIMIT ? OFFSET ?`,
    [...queryParams, pageSize, (page - 1) * pageSize],
  );

  return { items: items.values, total, page, page_size: pageSize };
}

/** Quick autocomplete search for customers */
export async function searchCustomers(q: string, limit = 20): Promise<any[]> {
  const db = await getDb();
  const term = `%${q}%`;
  const result = await db.query(
    `SELECT c.*,
       (SELECT COUNT(*) FROM job_customers jc WHERE jc.customer_id = c.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'customer' AND ec.entity_id = c.id AND ec.deleted_at IS NULL) as contact_count
     FROM customers c
     WHERE c.deleted_at IS NULL AND c.is_active = 1
       AND (c.name LIKE ? OR c.company_name LIKE ?)
     ORDER BY c.name ASC
     LIMIT ?`,
    [term, term, limit],
  );
  return result.values;
}

/** Full customer detail with contacts and job count */
export async function getCustomer(id: number): Promise<any | null> {
  const db = await getDb();
  const custResult = await db.query(
    `SELECT c.*,
       (SELECT COUNT(*) FROM job_customers jc WHERE jc.customer_id = c.id) as job_count
     FROM customers c
     WHERE c.id = ? AND c.deleted_at IS NULL`,
    [id],
  );
  const customer = custResult.values[0];
  if (!customer) return null;

  // Attach contacts
  const contactsResult = await db.query(
    `SELECT * FROM entity_contacts
     WHERE entity_type = 'customer' AND entity_id = ? AND deleted_at IS NULL
     ORDER BY is_primary DESC, first_name ASC`,
    [id],
  );
  customer.contacts = contactsResult.values;

  return customer;
}

/** Create a new customer */
export async function createCustomer(customer: Record<string, any>): Promise<any> {
  const now = new Date().toISOString();
  const id = await customerRepo.insert({
    name: customer.name ?? `${customer.first_name ?? ''} ${customer.last_name ?? ''}`.trim(),
    company_name: customer.company_name ?? null,
    customer_type: customer.customer_type ?? 'commercial',
    email: customer.email ?? null,
    phone: customer.phone ?? null,
    address: customer.address ?? null,
    city: customer.city ?? null,
    state: customer.state ?? null,
    zip: customer.zip ?? null,
    notes: customer.notes ?? null,
    is_active: 1,
    created_at: now,
    updated_at: now,
  });
  return getCustomer(id);
}

/** Update a customer */
export async function updateCustomer(id: number, updates: Record<string, any>): Promise<any> {
  await customerRepo.update(id, {
    ...updates,
    updated_at: new Date().toISOString(),
  });
  return getCustomer(id);
}

/** Activate or deactivate a customer */
export async function toggleCustomerActive(id: number, isActive: boolean): Promise<void> {
  await customerRepo.update(id, {
    is_active: isActive ? 1 : 0,
    updated_at: new Date().toISOString(),
  });
}

/** Get all contacts for a customer */
export async function getCustomerContacts(
  customerId: number,
  includeInactive = false,
): Promise<any[]> {
  const conditions: string[] = [
    "entity_type = 'customer'",
    'entity_id = ?',
    'deleted_at IS NULL',
  ];
  const params: any[] = [customerId];

  if (!includeInactive) {
    conditions.push('is_active = 1');
  }

  return (await contactRepo.findAll(
    conditions.join(' AND '),
    params,
    'is_primary DESC, first_name ASC',
  ));
}

/** Add a contact to a customer */
export async function addCustomerContact(
  customerId: number,
  contact: Record<string, any>,
): Promise<{ id: number }> {
  const now = new Date().toISOString();
  const id = await contactRepo.insert({
    entity_type: 'customer',
    entity_id: customerId,
    first_name: contact.first_name,
    last_name: contact.last_name,
    title: contact.title ?? contact.role ?? null,
    email: contact.email ?? null,
    phone: contact.phone ?? null,
    is_primary: contact.is_primary ? 1 : 0,
    is_active: 1,
    notes: contact.notes ?? null,
    created_at: now,
    updated_at: now,
  });
  return { id };
}

/** Get all jobs linked to a customer (reverse lookup) */
export async function getCustomerJobs(customerId: number): Promise<any[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jc.*, j.job_number, j.name as job_name, j.status as job_status,
       j.address as job_address, j.city as job_city, j.state as job_state
     FROM job_customers jc
     JOIN jobs j ON j.id = jc.job_id
     WHERE jc.customer_id = ? AND j.deleted_at IS NULL
     ORDER BY j.created_at DESC`,
    [customerId],
  );
  return result.values;
}

// ═══════════════════════════════════════════════════════════════════
// GENERAL CONTRACTORS
// ═══════════════════════════════════════════════════════════════════

export interface GCListParams {
  search?: string;
  trade_type?: string;
  is_active?: boolean;
  page?: number;
  page_size?: number;
}

/** Paginated GC list with job/contact counts */
export async function getGCs(
  params: GCListParams = {},
): Promise<PaginatedResult<any>> {
  const db = await getDb();
  const page = params.page ?? 1;
  const pageSize = params.page_size ?? 25;
  const conditions: string[] = ['g.deleted_at IS NULL'];
  const queryParams: any[] = [];

  if (params.search) {
    conditions.push('(g.company_name LIKE ? OR g.contact_name LIKE ? OR g.email LIKE ?)');
    const term = `%${params.search}%`;
    queryParams.push(term, term, term);
  }
  if (params.trade_type) {
    conditions.push('g.trade_type = ?');
    queryParams.push(params.trade_type);
  }
  if (params.is_active !== undefined) {
    conditions.push('g.is_active = ?');
    queryParams.push(params.is_active ? 1 : 0);
  }

  const whereClause = conditions.join(' AND ');

  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM general_contractors g WHERE ${whereClause}`,
    queryParams,
  );
  const total = countResult.values[0]?.cnt ?? 0;

  const items = await db.query(
    `SELECT g.*,
       (SELECT COUNT(*) FROM job_general_contractors jg WHERE jg.gc_id = g.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'gc' AND ec.entity_id = g.id AND ec.deleted_at IS NULL) as contact_count
     FROM general_contractors g
     WHERE ${whereClause}
     ORDER BY g.company_name ASC
     LIMIT ? OFFSET ?`,
    [...queryParams, pageSize, (page - 1) * pageSize],
  );

  return { items: items.values, total, page, page_size: pageSize };
}

/** Quick autocomplete search for GCs */
export async function searchGCs(q: string, limit = 20): Promise<any[]> {
  const db = await getDb();
  const term = `%${q}%`;
  const result = await db.query(
    `SELECT g.*,
       (SELECT COUNT(*) FROM job_general_contractors jg WHERE jg.gc_id = g.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'gc' AND ec.entity_id = g.id AND ec.deleted_at IS NULL) as contact_count
     FROM general_contractors g
     WHERE g.deleted_at IS NULL AND g.is_active = 1
       AND (g.company_name LIKE ? OR g.contact_name LIKE ?)
     ORDER BY g.company_name ASC
     LIMIT ?`,
    [term, term, limit],
  );
  return result.values;
}

/** Full GC detail with contacts and job count */
export async function getGC(id: number): Promise<any | null> {
  const db = await getDb();
  const gcResult = await db.query(
    `SELECT g.*,
       (SELECT COUNT(*) FROM job_general_contractors jg WHERE jg.gc_id = g.id) as job_count
     FROM general_contractors g
     WHERE g.id = ? AND g.deleted_at IS NULL`,
    [id],
  );
  const gc = gcResult.values[0];
  if (!gc) return null;

  const contactsResult = await db.query(
    `SELECT * FROM entity_contacts
     WHERE entity_type = 'gc' AND entity_id = ? AND deleted_at IS NULL
     ORDER BY is_primary DESC, first_name ASC`,
    [id],
  );
  gc.contacts = contactsResult.values;

  return gc;
}

/** Create a new general contractor */
export async function createGC(gc: Record<string, any>): Promise<any> {
  const now = new Date().toISOString();
  const id = await gcRepo.insert({
    company_name: gc.company_name,
    contact_name: gc.contact_name ?? null,
    email: gc.email ?? null,
    phone: gc.phone ?? null,
    address: gc.address ?? null,
    city: gc.city ?? null,
    state: gc.state ?? null,
    zip: gc.zip ?? null,
    relationship: gc.relationship ?? 'we_work_for_them',
    notes: gc.notes ?? null,
    is_active: 1,
    created_at: now,
    updated_at: now,
  });
  return getGC(id);
}

/** Update a general contractor */
export async function updateGC(id: number, updates: Record<string, any>): Promise<any> {
  await gcRepo.update(id, {
    ...updates,
    updated_at: new Date().toISOString(),
  });
  return getGC(id);
}

/** Activate or deactivate a GC */
export async function toggleGCActive(id: number, isActive: boolean): Promise<void> {
  await gcRepo.update(id, {
    is_active: isActive ? 1 : 0,
    updated_at: new Date().toISOString(),
  });
}

/** Get all contacts for a GC */
export async function getGCContacts(
  gcId: number,
  includeInactive = false,
): Promise<any[]> {
  const conditions: string[] = [
    "entity_type = 'gc'",
    'entity_id = ?',
    'deleted_at IS NULL',
  ];
  const params: any[] = [gcId];

  if (!includeInactive) {
    conditions.push('is_active = 1');
  }

  return contactRepo.findAll(
    conditions.join(' AND '),
    params,
    'is_primary DESC, first_name ASC',
  );
}

/** Add a contact to a GC */
export async function addGCContact(
  gcId: number,
  contact: Record<string, any>,
): Promise<{ id: number }> {
  const now = new Date().toISOString();
  const id = await contactRepo.insert({
    entity_type: 'gc',
    entity_id: gcId,
    first_name: contact.first_name,
    last_name: contact.last_name,
    title: contact.title ?? contact.role ?? null,
    email: contact.email ?? null,
    phone: contact.phone ?? null,
    is_primary: contact.is_primary ? 1 : 0,
    is_active: 1,
    notes: contact.notes ?? null,
    created_at: now,
    updated_at: now,
  });
  return { id };
}

/** Get all jobs linked to a GC (reverse lookup) */
export async function getGCJobs(gcId: number): Promise<any[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jg.*, j.job_number, j.name as job_name, j.status as job_status,
       j.address as job_address, j.city as job_city, j.state as job_state
     FROM job_general_contractors jg
     JOIN jobs j ON j.id = jg.job_id
     WHERE jg.gc_id = ? AND j.deleted_at IS NULL
     ORDER BY j.created_at DESC`,
    [gcId],
  );
  return result.values;
}

// ═══════════════════════════════════════════════════════════════════
// SUPPLIER CONTACTS
// ═══════════════════════════════════════════════════════════════════

/** Get all contacts for a supplier */
export async function getSupplierContacts(
  supplierId: number,
  includeInactive = false,
): Promise<any[]> {
  const conditions: string[] = [
    "entity_type = 'supplier'",
    'entity_id = ?',
    'deleted_at IS NULL',
  ];
  const params: any[] = [supplierId];

  if (!includeInactive) {
    conditions.push('is_active = 1');
  }

  return contactRepo.findAll(
    conditions.join(' AND '),
    params,
    'is_primary DESC, first_name ASC',
  );
}

/** Add a contact to a supplier */
export async function addSupplierContact(
  supplierId: number,
  contact: Record<string, any>,
): Promise<{ id: number }> {
  const now = new Date().toISOString();
  const id = await contactRepo.insert({
    entity_type: 'supplier',
    entity_id: supplierId,
    first_name: contact.first_name,
    last_name: contact.last_name,
    title: contact.title ?? contact.role ?? null,
    email: contact.email ?? null,
    phone: contact.phone ?? null,
    is_primary: contact.is_primary ? 1 : 0,
    is_active: 1,
    notes: contact.notes ?? null,
    created_at: now,
    updated_at: now,
  });
  return { id };
}

// ═══════════════════════════════════════════════════════════════════
// ENTITY CONTACTS (cross-entity operations)
// ═══════════════════════════════════════════════════════════════════

/**
 * Unified contact directory search across customers, GCs, and suppliers.
 * Joins entity_contacts with parent tables to enrich results with entity name and type.
 */
export async function searchDirectory(q: string, limit = 50): Promise<any[]> {
  const db = await getDb();
  const term = `%${q}%`;
  const result = await db.query(
    `SELECT ec.*,
       CASE ec.entity_type
         WHEN 'customer'  THEN (SELECT c.name FROM customers c WHERE c.id = ec.entity_id)
         WHEN 'gc'        THEN (SELECT g.company_name FROM general_contractors g WHERE g.id = ec.entity_id)
         WHEN 'supplier'  THEN (SELECT s.name FROM suppliers s WHERE s.id = ec.entity_id)
       END as entity_name
     FROM entity_contacts ec
     WHERE ec.deleted_at IS NULL
       AND (ec.first_name LIKE ? OR ec.last_name LIKE ? OR ec.email LIKE ? OR ec.phone LIKE ?)
     ORDER BY ec.first_name ASC, ec.last_name ASC
     LIMIT ?`,
    [term, term, term, term, limit],
  );
  return result.values;
}

/** Update an entity contact */
export async function updateEntityContact(
  contactId: number,
  updates: Record<string, any>,
): Promise<{ id: number }> {
  await contactRepo.update(contactId, {
    ...updates,
    updated_at: new Date().toISOString(),
  });
  return { id: contactId };
}

/** Soft-delete an entity contact */
export async function deleteEntityContact(contactId: number): Promise<{ id: number }> {
  await contactRepo.update(contactId, {
    deleted_at: new Date().toISOString(),
  });
  return { id: contactId };
}

// ═══════════════════════════════════════════════════════════════════
// JOB <-> CUSTOMER LINKING
// ═══════════════════════════════════════════════════════════════════

/** Get all customers linked to a job */
export async function getJobCustomers(jobId: number): Promise<any[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jc.*, c.name as customer_name, c.company_name,
       c.email, c.phone, c.is_active
     FROM job_customers jc
     JOIN customers c ON c.id = jc.customer_id
     WHERE jc.job_id = ? AND c.deleted_at IS NULL
     ORDER BY c.name ASC`,
    [jobId],
  );
  return result.values;
}

/** Link a customer to a job */
export async function linkCustomerToJob(
  jobId: number,
  link: Record<string, any>,
): Promise<{ id: number }> {
  const id = await jobCustomerRepo.insert({
    job_id: jobId,
    customer_id: link.customer_id,
    role: link.contact_role ?? link.role ?? null,
    created_at: new Date().toISOString(),
  });
  return { id };
}

/** Unlink a customer from a job */
export async function unlinkCustomerFromJob(
  _jobId: number,
  linkId: number,
): Promise<void> {
  // Hard delete — link rows are lightweight join entries
  await jobCustomerRepo.delete(linkId);
}

// ═══════════════════════════════════════════════════════════════════
// JOB <-> GENERAL CONTRACTOR LINKING
// ═══════════════════════════════════════════════════════════════════

/** Get all GCs linked to a job */
export async function getJobGCs(jobId: number): Promise<any[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jg.*, g.company_name, g.contact_name,
       g.email, g.phone, g.is_active
     FROM job_general_contractors jg
     JOIN general_contractors g ON g.id = jg.gc_id
     WHERE jg.job_id = ? AND g.deleted_at IS NULL
     ORDER BY g.company_name ASC`,
    [jobId],
  );
  return result.values;
}

/** Link a GC to a job */
export async function linkGCToJob(
  jobId: number,
  link: Record<string, any>,
): Promise<{ id: number }> {
  const id = await jobGCRepo.insert({
    job_id: jobId,
    gc_id: link.gc_id,
    role: link.relationship ?? link.role ?? null,
    created_at: new Date().toISOString(),
  });
  return { id };
}

/** Unlink a GC from a job */
export async function unlinkGCFromJob(
  _jobId: number,
  linkId: number,
): Promise<void> {
  await jobGCRepo.delete(linkId);
}

// ═══════════════════════════════════════════════════════════════════
// CSV IMPORT
// ═══════════════════════════════════════════════════════════════════

/**
 * Import customers from pre-parsed CSV rows.
 * Each row should have: name, company_name?, email?, phone?, address?, city?, state?, zip?, customer_type?
 */
export async function importCustomersCSV(
  rows: Record<string, any>[],
): Promise<CSVImportResult> {
  const result: CSVImportResult = { created: 0, skipped: 0, errors: [] };
  const now = new Date().toISOString();

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    try {
      const name = (row.name ?? '').trim();
      if (!name) {
        result.skipped++;
        continue;
      }

      // Check for exact name duplicate
      const existing = await customerRepo.findAll(
        'name = ? AND deleted_at IS NULL',
        [name],
      );
      if (existing.length > 0) {
        result.skipped++;
        continue;
      }

      await customerRepo.insert({
        name,
        company_name: row.company_name ?? null,
        customer_type: row.customer_type ?? 'commercial',
        email: row.email ?? null,
        phone: row.phone ?? null,
        address: row.address ?? null,
        city: row.city ?? null,
        state: row.state ?? null,
        zip: row.zip ?? null,
        notes: row.notes ?? null,
        is_active: 1,
        created_at: now,
        updated_at: now,
      });
      result.created++;
    } catch (err: any) {
      result.errors.push({ row: i + 1, error: err.message ?? String(err) });
    }
  }

  return result;
}

/**
 * Import general contractors from pre-parsed CSV rows.
 * Each row should have: company_name, contact_name?, email?, phone?, address?, city?, state?, zip?, relationship?
 */
export async function importContractorsCSV(
  rows: Record<string, any>[],
): Promise<CSVImportResult> {
  const result: CSVImportResult = { created: 0, skipped: 0, errors: [] };
  const now = new Date().toISOString();

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    try {
      const companyName = (row.company_name ?? '').trim();
      if (!companyName) {
        result.skipped++;
        continue;
      }

      // Check for exact company_name duplicate
      const existing = await gcRepo.findAll(
        'company_name = ? AND deleted_at IS NULL',
        [companyName],
      );
      if (existing.length > 0) {
        result.skipped++;
        continue;
      }

      await gcRepo.insert({
        company_name: companyName,
        contact_name: row.contact_name ?? null,
        email: row.email ?? null,
        phone: row.phone ?? null,
        address: row.address ?? null,
        city: row.city ?? null,
        state: row.state ?? null,
        zip: row.zip ?? null,
        relationship: row.relationship ?? 'we_work_for_them',
        notes: row.notes ?? null,
        is_active: 1,
        created_at: now,
        updated_at: now,
      });
      result.created++;
    } catch (err: any) {
      result.errors.push({ row: i + 1, error: err.message ?? String(err) });
    }
  }

  return result;
}

// ═══════════════════════════════════════════════════════════════════
// CONTACT DEDUPE / MERGE
// ═══════════════════════════════════════════════════════════════════

/**
 * Find potential duplicate customers by matching name, email, or phone.
 * Uses simple exact-match and LIKE comparisons — no fuzzy scoring engine.
 * The `threshold` parameter is accepted for API compatibility but matching
 * is binary (exact email/phone = 1.0, same-name substring = 0.8).
 */
export async function findDuplicateCustomers(
  _threshold = 0.8,
): Promise<DuplicatePair[]> {
  const db = await getDb();
  const pairs: DuplicatePair[] = [];

  // 1) Exact email matches (different IDs)
  const emailDupes = await db.query(
    `SELECT a.id as a_id, a.name as a_name, a.email as a_email, a.phone as a_phone,
            b.id as b_id, b.name as b_name, b.email as b_email, b.phone as b_phone
     FROM customers a
     JOIN customers b ON a.email = b.email AND a.id < b.id
     WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL
       AND a.email IS NOT NULL AND a.email != ''`,
  );
  for (const row of emailDupes.values) {
    pairs.push({
      a: { id: row.a_id, name: row.a_name, email: row.a_email, phone: row.a_phone },
      b: { id: row.b_id, name: row.b_name, email: row.b_email, phone: row.b_phone },
      similarity: 1.0,
      match_type: 'email',
    });
  }

  // 2) Exact phone matches (different IDs, not already matched by email)
  const phoneDupes = await db.query(
    `SELECT a.id as a_id, a.name as a_name, a.email as a_email, a.phone as a_phone,
            b.id as b_id, b.name as b_name, b.email as b_email, b.phone as b_phone
     FROM customers a
     JOIN customers b ON a.phone = b.phone AND a.id < b.id
     WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL
       AND a.phone IS NOT NULL AND a.phone != ''
       AND (a.email IS NULL OR b.email IS NULL OR a.email != b.email)`,
  );
  for (const row of phoneDupes.values) {
    pairs.push({
      a: { id: row.a_id, name: row.a_name, email: row.a_email, phone: row.a_phone },
      b: { id: row.b_id, name: row.b_name, email: row.b_email, phone: row.b_phone },
      similarity: 0.9,
      match_type: 'phone',
    });
  }

  // 3) Exact name matches (different IDs, not already matched above)
  const existingPairIds = new Set(pairs.map((p) => `${p.a.id}-${p.b.id}`));
  const nameDupes = await db.query(
    `SELECT a.id as a_id, a.name as a_name, a.email as a_email, a.phone as a_phone,
            b.id as b_id, b.name as b_name, b.email as b_email, b.phone as b_phone
     FROM customers a
     JOIN customers b ON LOWER(a.name) = LOWER(b.name) AND a.id < b.id
     WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL`,
  );
  for (const row of nameDupes.values) {
    const key = `${row.a_id}-${row.b_id}`;
    if (!existingPairIds.has(key)) {
      pairs.push({
        a: { id: row.a_id, name: row.a_name, email: row.a_email, phone: row.a_phone },
        b: { id: row.b_id, name: row.b_name, email: row.b_email, phone: row.b_phone },
        similarity: 0.8,
        match_type: 'name',
      });
    }
  }

  return pairs;
}

/**
 * Merge two customers: move all contacts and job links from mergeId to keepId,
 * then deactivate the merged customer.
 */
export async function mergeCustomers(
  keepId: number,
  mergeId: number,
): Promise<{ keep_id: number; merged_id: number }> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Move entity_contacts from mergeId to keepId
  await db.run(
    `UPDATE entity_contacts
     SET entity_id = ?, updated_at = ?
     WHERE entity_type = 'customer' AND entity_id = ? AND deleted_at IS NULL`,
    [keepId, now, mergeId],
  );

  // Move job_customers links from mergeId to keepId (skip duplicates)
  await db.run(
    `UPDATE job_customers
     SET customer_id = ?
     WHERE customer_id = ?
       AND job_id NOT IN (SELECT job_id FROM job_customers WHERE customer_id = ?)`,
    [keepId, mergeId, keepId],
  );

  // Delete any remaining duplicate job links for mergeId
  await db.run(
    `DELETE FROM job_customers WHERE customer_id = ?`,
    [mergeId],
  );

  // Deactivate the merged customer
  await customerRepo.update(mergeId, {
    is_active: 0,
    notes: `Merged into customer #${keepId} on ${now}`,
    updated_at: now,
  });

  return { keep_id: keepId, merged_id: mergeId };
}
