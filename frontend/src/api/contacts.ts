/**
 * Contacts API functions — customers, general contractors, entity contacts,
 * directory search, and job linking.
 *
 * All functions follow: call apiClient -> unwrap ApiResponse -> return typed data.
 */

import apiClient from './client';
import type {
  ApiResponse,
  PaginatedData,
  // Customers
  CustomerListItem,
  CustomerDetail,
  CustomerCreate,
  CustomerUpdate,
  // General Contractors
  GCListItem,
  GCDetail,
  GCCreate,
  GCUpdate,
  // Entity Contacts
  EntityContactResponse,
  EntityContactCreate,
  EntityContactUpdate,
  DirectoryContactResult,
  // Job linking
  JobCustomerResponse,
  JobCustomerCreate,
  JobGCResponse,
  JobGCCreate,
  // Reverse job links (entity → jobs)
  CustomerJobLink,
  GCJobLink,
} from '../lib/types';


// =================================================================
// CUSTOMERS
// =================================================================

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
): Promise<PaginatedData<CustomerListItem>> {
  const { data } = await apiClient.get<ApiResponse<PaginatedData<CustomerListItem>>>(
    '/contacts/customers',
    { params },
  );
  return data.data!;
}

/** Quick autocomplete search for customers */
export async function searchCustomers(
  q: string,
  limit = 20,
): Promise<CustomerListItem[]> {
  const { data } = await apiClient.get<ApiResponse<CustomerListItem[]>>(
    '/contacts/customers/search',
    { params: { q, limit } },
  );
  return data.data!;
}

/** Full customer detail with contacts and job count */
export async function getCustomer(customerId: number): Promise<CustomerDetail> {
  const { data } = await apiClient.get<ApiResponse<CustomerDetail>>(
    `/contacts/customers/${customerId}`,
  );
  return data.data!;
}

/** Create a new customer */
export async function createCustomer(customer: CustomerCreate): Promise<CustomerDetail> {
  const { data } = await apiClient.post<ApiResponse<CustomerDetail>>(
    '/contacts/customers',
    customer,
  );
  return data.data!;
}

/** Update a customer */
export async function updateCustomer(
  customerId: number,
  updates: CustomerUpdate,
): Promise<CustomerDetail> {
  const { data } = await apiClient.put<ApiResponse<CustomerDetail>>(
    `/contacts/customers/${customerId}`,
    updates,
  );
  return data.data!;
}

/** Activate or deactivate a customer */
export async function toggleCustomerActive(
  customerId: number,
  isActive: boolean,
): Promise<void> {
  await apiClient.patch(
    `/contacts/customers/${customerId}/toggle-active`,
    null,
    { params: { is_active: isActive } },
  );
}

/** Get all contacts for a customer */
export async function getCustomerContacts(
  customerId: number,
  includeInactive = false,
): Promise<EntityContactResponse[]> {
  const { data } = await apiClient.get<ApiResponse<EntityContactResponse[]>>(
    `/contacts/customers/${customerId}/contacts`,
    { params: { include_inactive: includeInactive } },
  );
  return data.data!;
}

/** Add a contact to a customer */
export async function addCustomerContact(
  customerId: number,
  contact: EntityContactCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/contacts/customers/${customerId}/contacts`,
    contact,
  );
  return data.data!;
}

/** Get all jobs linked to a customer (reverse lookup) */
export async function getCustomerJobs(
  customerId: number,
): Promise<CustomerJobLink[]> {
  const { data } = await apiClient.get<ApiResponse<CustomerJobLink[]>>(
    `/contacts/customers/${customerId}/jobs`,
  );
  return data.data!;
}


// =================================================================
// GENERAL CONTRACTORS
// =================================================================

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
): Promise<PaginatedData<GCListItem>> {
  const { data } = await apiClient.get<ApiResponse<PaginatedData<GCListItem>>>(
    '/contacts/general-contractors',
    { params },
  );
  return data.data!;
}

/** Quick autocomplete search for GCs */
export async function searchGCs(
  q: string,
  limit = 20,
): Promise<GCListItem[]> {
  const { data } = await apiClient.get<ApiResponse<GCListItem[]>>(
    '/contacts/general-contractors/search',
    { params: { q, limit } },
  );
  return data.data!;
}

/** Full GC detail with contacts and job count */
export async function getGC(gcId: number): Promise<GCDetail> {
  const { data } = await apiClient.get<ApiResponse<GCDetail>>(
    `/contacts/general-contractors/${gcId}`,
  );
  return data.data!;
}

/** Create a new general contractor */
export async function createGC(gc: GCCreate): Promise<GCDetail> {
  const { data } = await apiClient.post<ApiResponse<GCDetail>>(
    '/contacts/general-contractors',
    gc,
  );
  return data.data!;
}

/** Update a general contractor */
export async function updateGC(
  gcId: number,
  updates: GCUpdate,
): Promise<GCDetail> {
  const { data } = await apiClient.put<ApiResponse<GCDetail>>(
    `/contacts/general-contractors/${gcId}`,
    updates,
  );
  return data.data!;
}

/** Activate or deactivate a GC */
export async function toggleGCActive(
  gcId: number,
  isActive: boolean,
): Promise<void> {
  await apiClient.patch(
    `/contacts/general-contractors/${gcId}/toggle-active`,
    null,
    { params: { is_active: isActive } },
  );
}

/** Get all contacts for a GC */
export async function getGCContacts(
  gcId: number,
  includeInactive = false,
): Promise<EntityContactResponse[]> {
  const { data } = await apiClient.get<ApiResponse<EntityContactResponse[]>>(
    `/contacts/general-contractors/${gcId}/contacts`,
    { params: { include_inactive: includeInactive } },
  );
  return data.data!;
}

/** Add a contact to a GC */
export async function addGCContact(
  gcId: number,
  contact: EntityContactCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/contacts/general-contractors/${gcId}/contacts`,
    contact,
  );
  return data.data!;
}

/** Get all jobs linked to a GC (reverse lookup) */
export async function getGCJobs(
  gcId: number,
): Promise<GCJobLink[]> {
  const { data } = await apiClient.get<ApiResponse<GCJobLink[]>>(
    `/contacts/general-contractors/${gcId}/jobs`,
  );
  return data.data!;
}


// =================================================================
// SUPPLIER CONTACTS (entity_contacts for suppliers)
// =================================================================

/** Get all contacts for a supplier */
export async function getSupplierContacts(
  supplierId: number,
  includeInactive = false,
): Promise<EntityContactResponse[]> {
  const { data } = await apiClient.get<ApiResponse<EntityContactResponse[]>>(
    `/contacts/suppliers/${supplierId}/contacts`,
    { params: { include_inactive: includeInactive } },
  );
  return data.data!;
}

/** Add a contact to a supplier */
export async function addSupplierContact(
  supplierId: number,
  contact: EntityContactCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/contacts/suppliers/${supplierId}/contacts`,
    contact,
  );
  return data.data!;
}


// =================================================================
// ENTITY CONTACTS (cross-entity operations)
// =================================================================

/** Unified contact directory search across customers, GCs, suppliers */
export async function searchDirectory(
  q: string,
  limit = 50,
): Promise<DirectoryContactResult[]> {
  const { data } = await apiClient.get<ApiResponse<DirectoryContactResult[]>>(
    '/contacts/directory',
    { params: { q, limit } },
  );
  return data.data!;
}

/** Update an entity contact */
export async function updateEntityContact(
  contactId: number,
  updates: EntityContactUpdate,
): Promise<{ id: number }> {
  const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
    `/contacts/entity-contacts/${contactId}`,
    updates,
  );
  return data.data!;
}

/** Soft-delete an entity contact */
export async function deleteEntityContact(
  contactId: number,
): Promise<{ id: number }> {
  const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
    `/contacts/entity-contacts/${contactId}`,
  );
  return data.data!;
}


// =================================================================
// JOB <-> CUSTOMER LINKING
// =================================================================

/** Get all customers linked to a job */
export async function getJobCustomers(jobId: number): Promise<JobCustomerResponse[]> {
  const { data } = await apiClient.get<ApiResponse<JobCustomerResponse[]>>(
    `/jobs/${jobId}/customers`,
  );
  return data.data!;
}

/** Link a customer to a job */
export async function linkCustomerToJob(
  jobId: number,
  link: JobCustomerCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/jobs/${jobId}/customers`,
    link,
  );
  return data.data!;
}

/** Unlink a customer from a job */
export async function unlinkCustomerFromJob(
  jobId: number,
  linkId: number,
): Promise<void> {
  await apiClient.delete(`/jobs/${jobId}/customers/${linkId}`);
}


// =================================================================
// JOB <-> GENERAL CONTRACTOR LINKING
// =================================================================

/** Get all GCs linked to a job */
export async function getJobGCs(jobId: number): Promise<JobGCResponse[]> {
  const { data } = await apiClient.get<ApiResponse<JobGCResponse[]>>(
    `/jobs/${jobId}/general-contractors`,
  );
  return data.data!;
}

/** Link a GC to a job */
export async function linkGCToJob(
  jobId: number,
  link: JobGCCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/jobs/${jobId}/general-contractors`,
    link,
  );
  return data.data!;
}

/** Unlink a GC from a job */
export async function unlinkGCFromJob(
  jobId: number,
  linkId: number,
): Promise<void> {
  await apiClient.delete(`/jobs/${jobId}/general-contractors/${linkId}`);
}


// =================================================================
// CSV IMPORT
// =================================================================

export interface CSVImportResult {
  created: number;
  skipped: number;
  errors: { row: number; error: string }[];
}

/** Import customers from a CSV file */
export async function importCustomersCSV(file: File): Promise<CSVImportResult> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<CSVImportResult>>(
    '/contacts/import/customers',
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}

/** Import general contractors from a CSV file */
export async function importContractorsCSV(file: File): Promise<CSVImportResult> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<CSVImportResult>>(
    '/contacts/import/contractors',
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}


// =================================================================
// CONTACT DEDUPE / MERGE
// =================================================================

export interface DuplicatePair {
  a: { id: number; name: string; email?: string; phone?: string };
  b: { id: number; name: string; email?: string; phone?: string };
  similarity: number;
  match_type: string;
}

/** Find potential duplicate customers */
export async function findDuplicateCustomers(
  threshold = 0.8,
): Promise<DuplicatePair[]> {
  const { data } = await apiClient.get<ApiResponse<DuplicatePair[]>>(
    '/contacts/dedupe/customers',
    { params: { threshold } },
  );
  return data.data ?? [];
}

/** Merge two customers: keep one, deactivate the other */
export async function mergeCustomers(
  keepId: number,
  mergeId: number,
): Promise<{ keep_id: number; merged_id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ keep_id: number; merged_id: number }>>(
    '/contacts/merge/customers',
    { keep_id: keepId, merge_id: mergeId },
  );
  return data.data!;
}
