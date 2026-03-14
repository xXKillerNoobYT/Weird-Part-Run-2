/**
 * Contacts API functions — customers, general contractors, entity contacts,
 * directory search, and job linking.
 *
 * All functions follow: call apiClient -> unwrap ApiResponse -> return typed data.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PaginatedData<CustomerListItem>>>(
        '/contacts/customers',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getCustomers } = await import('../local/services/contacts-service');
      return getCustomers(params) as unknown as PaginatedData<CustomerListItem>;
    },
  );
}

/** Quick autocomplete search for customers */
export async function searchCustomers(
  q: string,
  limit = 20,
): Promise<CustomerListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CustomerListItem[]>>(
        '/contacts/customers/search',
        { params: { q, limit } },
      );
      return data.data!;
    },
    async () => {
      const { searchCustomers } = await import('../local/services/contacts-service');
      return searchCustomers(q, limit) as unknown as CustomerListItem[];
    },
  );
}

/** Full customer detail with contacts and job count */
export async function getCustomer(customerId: number): Promise<CustomerDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CustomerDetail>>(
        `/contacts/customers/${customerId}`,
      );
      return data.data!;
    },
    async () => {
      const { getCustomer } = await import('../local/services/contacts-service');
      return getCustomer(customerId) as unknown as CustomerDetail;
    },
  );
}

/** Create a new customer */
export async function createCustomer(customer: CustomerCreate): Promise<CustomerDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<CustomerDetail>>(
        '/contacts/customers',
        customer,
      );
      return data.data!;
    },
    async () => {
      const { createCustomer } = await import('../local/services/contacts-service');
      return createCustomer(customer) as unknown as CustomerDetail;
    },
  );
}

/** Update a customer */
export async function updateCustomer(
  customerId: number,
  updates: CustomerUpdate,
): Promise<CustomerDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<CustomerDetail>>(
        `/contacts/customers/${customerId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateCustomer } = await import('../local/services/contacts-service');
      return updateCustomer(customerId, updates) as unknown as CustomerDetail;
    },
  );
}

/** Activate or deactivate a customer */
export async function toggleCustomerActive(
  customerId: number,
  isActive: boolean,
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.patch(
        `/contacts/customers/${customerId}/toggle-active`,
        null,
        { params: { is_active: isActive } },
      );
    },
    async () => {
      const { toggleCustomerActive } = await import('../local/services/contacts-service');
      await toggleCustomerActive(customerId, isActive);
    },
  );
}

/** Get all contacts for a customer */
export async function getCustomerContacts(
  customerId: number,
  includeInactive = false,
): Promise<EntityContactResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EntityContactResponse[]>>(
        `/contacts/customers/${customerId}/contacts`,
        { params: { include_inactive: includeInactive } },
      );
      return data.data!;
    },
    async () => {
      const { getCustomerContacts } = await import('../local/services/contacts-service');
      return getCustomerContacts(customerId, includeInactive) as unknown as EntityContactResponse[];
    },
  );
}

/** Add a contact to a customer */
export async function addCustomerContact(
  customerId: number,
  contact: EntityContactCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/contacts/customers/${customerId}/contacts`,
        contact,
      );
      return data.data!;
    },
    async () => {
      const { addCustomerContact } = await import('../local/services/contacts-service');
      return addCustomerContact(customerId, contact) as unknown as { id: number };
    },
  );
}

/** Get all jobs linked to a customer (reverse lookup) */
export async function getCustomerJobs(
  customerId: number,
): Promise<CustomerJobLink[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CustomerJobLink[]>>(
        `/contacts/customers/${customerId}/jobs`,
      );
      return data.data!;
    },
    async () => {
      const { getCustomerJobs } = await import('../local/services/contacts-service');
      return getCustomerJobs(customerId) as unknown as CustomerJobLink[];
    },
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PaginatedData<GCListItem>>>(
        '/contacts/general-contractors',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getGCs } = await import('../local/services/contacts-service');
      return getGCs(params) as unknown as PaginatedData<GCListItem>;
    },
  );
}

/** Quick autocomplete search for GCs */
export async function searchGCs(
  q: string,
  limit = 20,
): Promise<GCListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<GCListItem[]>>(
        '/contacts/general-contractors/search',
        { params: { q, limit } },
      );
      return data.data!;
    },
    async () => {
      const { searchGCs } = await import('../local/services/contacts-service');
      return searchGCs(q, limit) as unknown as GCListItem[];
    },
  );
}

/** Full GC detail with contacts and job count */
export async function getGC(gcId: number): Promise<GCDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<GCDetail>>(
        `/contacts/general-contractors/${gcId}`,
      );
      return data.data!;
    },
    async () => {
      const { getGC } = await import('../local/services/contacts-service');
      return getGC(gcId) as unknown as GCDetail;
    },
  );
}

/** Create a new general contractor */
export async function createGC(gc: GCCreate): Promise<GCDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<GCDetail>>(
        '/contacts/general-contractors',
        gc,
      );
      return data.data!;
    },
    async () => {
      const { createGC } = await import('../local/services/contacts-service');
      return createGC(gc) as unknown as GCDetail;
    },
  );
}

/** Update a general contractor */
export async function updateGC(
  gcId: number,
  updates: GCUpdate,
): Promise<GCDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<GCDetail>>(
        `/contacts/general-contractors/${gcId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateGC } = await import('../local/services/contacts-service');
      return updateGC(gcId, updates) as unknown as GCDetail;
    },
  );
}

/** Activate or deactivate a GC */
export async function toggleGCActive(
  gcId: number,
  isActive: boolean,
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.patch(
        `/contacts/general-contractors/${gcId}/toggle-active`,
        null,
        { params: { is_active: isActive } },
      );
    },
    async () => {
      const { toggleGCActive } = await import('../local/services/contacts-service');
      await toggleGCActive(gcId, isActive);
    },
  );
}

/** Get all contacts for a GC */
export async function getGCContacts(
  gcId: number,
  includeInactive = false,
): Promise<EntityContactResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EntityContactResponse[]>>(
        `/contacts/general-contractors/${gcId}/contacts`,
        { params: { include_inactive: includeInactive } },
      );
      return data.data!;
    },
    async () => {
      const { getGCContacts } = await import('../local/services/contacts-service');
      return getGCContacts(gcId, includeInactive) as unknown as EntityContactResponse[];
    },
  );
}

/** Add a contact to a GC */
export async function addGCContact(
  gcId: number,
  contact: EntityContactCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/contacts/general-contractors/${gcId}/contacts`,
        contact,
      );
      return data.data!;
    },
    async () => {
      const { addGCContact } = await import('../local/services/contacts-service');
      return addGCContact(gcId, contact) as unknown as { id: number };
    },
  );
}

/** Get all jobs linked to a GC (reverse lookup) */
export async function getGCJobs(
  gcId: number,
): Promise<GCJobLink[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<GCJobLink[]>>(
        `/contacts/general-contractors/${gcId}/jobs`,
      );
      return data.data!;
    },
    async () => {
      const { getGCJobs } = await import('../local/services/contacts-service');
      return getGCJobs(gcId) as unknown as GCJobLink[];
    },
  );
}


// =================================================================
// SUPPLIER CONTACTS (entity_contacts for suppliers)
// =================================================================

/** Get all contacts for a supplier */
export async function getSupplierContacts(
  supplierId: number,
  includeInactive = false,
): Promise<EntityContactResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EntityContactResponse[]>>(
        `/contacts/suppliers/${supplierId}/contacts`,
        { params: { include_inactive: includeInactive } },
      );
      return data.data!;
    },
    async () => {
      const { getSupplierContacts } = await import('../local/services/contacts-service');
      return getSupplierContacts(supplierId, includeInactive) as unknown as EntityContactResponse[];
    },
  );
}

/** Add a contact to a supplier */
export async function addSupplierContact(
  supplierId: number,
  contact: EntityContactCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/contacts/suppliers/${supplierId}/contacts`,
        contact,
      );
      return data.data!;
    },
    async () => {
      const { addSupplierContact } = await import('../local/services/contacts-service');
      return addSupplierContact(supplierId, contact) as unknown as { id: number };
    },
  );
}


// =================================================================
// ENTITY CONTACTS (cross-entity operations)
// =================================================================

/** Unified contact directory search across customers, GCs, suppliers */
export async function searchDirectory(
  q: string,
  limit = 50,
): Promise<DirectoryContactResult[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DirectoryContactResult[]>>(
        '/contacts/directory',
        { params: { q, limit } },
      );
      return data.data!;
    },
    async () => {
      const { searchDirectory } = await import('../local/services/contacts-service');
      return searchDirectory(q, limit) as unknown as DirectoryContactResult[];
    },
  );
}

/** Update an entity contact */
export async function updateEntityContact(
  contactId: number,
  updates: EntityContactUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/contacts/entity-contacts/${contactId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateEntityContact } = await import('../local/services/contacts-service');
      return updateEntityContact(contactId, updates) as unknown as { id: number };
    },
  );
}

/** Soft-delete an entity contact */
export async function deleteEntityContact(
  contactId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
        `/contacts/entity-contacts/${contactId}`,
      );
      return data.data!;
    },
    async () => {
      const { deleteEntityContact } = await import('../local/services/contacts-service');
      return deleteEntityContact(contactId) as unknown as { id: number };
    },
  );
}


// =================================================================
// JOB <-> CUSTOMER LINKING
// =================================================================

/** Get all customers linked to a job */
export async function getJobCustomers(jobId: number): Promise<JobCustomerResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobCustomerResponse[]>>(
        `/jobs/${jobId}/customers`,
      );
      return data.data!;
    },
    async () => {
      const { getJobCustomers } = await import('../local/services/contacts-service');
      return getJobCustomers(jobId) as unknown as JobCustomerResponse[];
    },
  );
}

/** Link a customer to a job */
export async function linkCustomerToJob(
  jobId: number,
  link: JobCustomerCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/jobs/${jobId}/customers`,
        link,
      );
      return data.data!;
    },
    async () => {
      const { linkCustomerToJob } = await import('../local/services/contacts-service');
      return linkCustomerToJob(jobId, link) as unknown as { id: number };
    },
  );
}

/** Unlink a customer from a job */
export async function unlinkCustomerFromJob(
  jobId: number,
  linkId: number,
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/jobs/${jobId}/customers/${linkId}`);
    },
    async () => {
      const { unlinkCustomerFromJob } = await import('../local/services/contacts-service');
      await unlinkCustomerFromJob(jobId, linkId);
    },
  );
}


// =================================================================
// JOB <-> GENERAL CONTRACTOR LINKING
// =================================================================

/** Get all GCs linked to a job */
export async function getJobGCs(jobId: number): Promise<JobGCResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobGCResponse[]>>(
        `/jobs/${jobId}/general-contractors`,
      );
      return data.data!;
    },
    async () => {
      const { getJobGCs } = await import('../local/services/contacts-service');
      return getJobGCs(jobId) as unknown as JobGCResponse[];
    },
  );
}

/** Link a GC to a job */
export async function linkGCToJob(
  jobId: number,
  link: JobGCCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/jobs/${jobId}/general-contractors`,
        link,
      );
      return data.data!;
    },
    async () => {
      const { linkGCToJob } = await import('../local/services/contacts-service');
      return linkGCToJob(jobId, link) as unknown as { id: number };
    },
  );
}

/** Unlink a GC from a job */
export async function unlinkGCFromJob(
  jobId: number,
  linkId: number,
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/jobs/${jobId}/general-contractors/${linkId}`);
    },
    async () => {
      const { unlinkGCFromJob } = await import('../local/services/contacts-service');
      await unlinkGCFromJob(jobId, linkId);
    },
  );
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
  return adaptedRequest(
    async () => {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await apiClient.post<ApiResponse<CSVImportResult>>(
        '/contacts/import/customers',
        formData,
        { headers: { 'Content-Type': 'multipart/form-data' } },
      );
      return data.data!;
    },
    async () => {
      const { importCustomersCSV } = await import('../local/services/contacts-service');
      return importCustomersCSV(file as any) as unknown as CSVImportResult;
    },
  );
}

/** Import general contractors from a CSV file */
export async function importContractorsCSV(file: File): Promise<CSVImportResult> {
  return adaptedRequest(
    async () => {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await apiClient.post<ApiResponse<CSVImportResult>>(
        '/contacts/import/contractors',
        formData,
        { headers: { 'Content-Type': 'multipart/form-data' } },
      );
      return data.data!;
    },
    async () => {
      const { importContractorsCSV } = await import('../local/services/contacts-service');
      return importContractorsCSV(file as any) as unknown as CSVImportResult;
    },
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DuplicatePair[]>>(
        '/contacts/dedupe/customers',
        { params: { threshold } },
      );
      return data.data ?? [];
    },
    async () => {
      const { findDuplicateCustomers } = await import('../local/services/contacts-service');
      return findDuplicateCustomers(threshold) as unknown as DuplicatePair[];
    },
  );
}

/** Merge two customers: keep one, deactivate the other */
export async function mergeCustomers(
  keepId: number,
  mergeId: number,
): Promise<{ keep_id: number; merged_id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ keep_id: number; merged_id: number }>>(
        '/contacts/merge/customers',
        { keep_id: keepId, merge_id: mergeId },
      );
      return data.data!;
    },
    async () => {
      const { mergeCustomers } = await import('../local/services/contacts-service');
      return mergeCustomers(keepId, mergeId) as unknown as { keep_id: number; merged_id: number };
    },
  );
}
