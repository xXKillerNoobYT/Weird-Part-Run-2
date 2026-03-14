/**
 * Contacts types — customers, general contractors, entity contacts (polymorphic),
 * job ↔ customer/GC linking.
 */

// ══════════════════════════════════════════════════════════════════
// CUSTOMERS
// ══════════════════════════════════════════════════════════════════

export type CustomerType = 'residential' | 'commercial' | 'government' | 'other';

export interface CustomerListItem {
  id: number;
  company_name: string | null;
  first_name: string;
  last_name: string;
  display_name: string;
  phone: string | null;
  email: string | null;
  customer_type: CustomerType;
  is_active: boolean;
  job_count: number;
  contact_count: number;
}

export type PaymentTerms = 'due_on_receipt' | 'net_15' | 'net_30' | 'net_45' | 'net_60' | 'custom';

export interface CustomerDetail {
  id: number;
  company_name: string | null;
  company_code: string | null;
  first_name: string;
  last_name: string;
  display_name: string;
  phone: string | null;
  email: string | null;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  customer_type: CustomerType;
  notes: string | null;
  is_active: boolean;
  contacts: EntityContactResponse[];
  job_count: number;
  created_at: string | null;
  updated_at: string | null;
  // Billing
  billing_address_line1: string | null;
  billing_address_line2: string | null;
  billing_city: string | null;
  billing_state: string | null;
  billing_zip: string | null;
  payment_terms: PaymentTerms;
  tax_id: string | null;
  billing_email: string | null;
}

export interface CustomerCreate {
  company_name?: string | null;
  company_code?: string | null;
  first_name: string;
  last_name: string;
  phone?: string | null;
  email?: string | null;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  customer_type?: CustomerType;
  notes?: string | null;
  billing_address_line1?: string | null;
  billing_address_line2?: string | null;
  billing_city?: string | null;
  billing_state?: string | null;
  billing_zip?: string | null;
  payment_terms?: PaymentTerms;
  tax_id?: string | null;
  billing_email?: string | null;
}

export interface CustomerUpdate {
  company_name?: string | null;
  company_code?: string | null;
  first_name?: string;
  last_name?: string;
  phone?: string | null;
  email?: string | null;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  customer_type?: CustomerType;
  notes?: string | null;
  billing_address_line1?: string | null;
  billing_address_line2?: string | null;
  billing_city?: string | null;
  billing_state?: string | null;
  billing_zip?: string | null;
  payment_terms?: PaymentTerms;
  tax_id?: string | null;
  billing_email?: string | null;
}


// ══════════════════════════════════════════════════════════════════
// GENERAL CONTRACTORS
// ══════════════════════════════════════════════════════════════════

export type GCTradeType =
  | 'general'
  | 'electrical'
  | 'plumbing'
  | 'hvac'
  | 'mechanical'
  | 'fire_protection'
  | 'low_voltage'
  | 'other';

export interface GCListItem {
  id: number;
  company_name: string;
  gc_code: string;
  trade_type: GCTradeType;
  phone: string | null;
  email: string | null;
  is_active: boolean;
  job_count: number;
  contact_count: number;
}

export interface GCDetail {
  id: number;
  company_name: string;
  gc_code: string;
  license_number: string | null;
  trade_type: GCTradeType;
  phone: string | null;
  email: string | null;
  website: string | null;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  insurance_info: string | null;
  notes: string | null;
  is_active: boolean;
  contacts: EntityContactResponse[];
  job_count: number;
  created_at: string | null;
  updated_at: string | null;
  // COI tracking
  coi_carrier: string | null;
  coi_policy_number: string | null;
  coi_expiry_date: string | null;
  coi_coverage_amount: number | null;
  coi_on_file: boolean;
  workers_comp_expiry: string | null;
  bonded: boolean;
  bond_amount: number | null;
}

export interface GCCreate {
  company_name: string;
  gc_code: string;
  license_number?: string | null;
  trade_type?: GCTradeType;
  phone?: string | null;
  email?: string | null;
  website?: string | null;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  insurance_info?: string | null;
  notes?: string | null;
  coi_carrier?: string | null;
  coi_policy_number?: string | null;
  coi_expiry_date?: string | null;
  coi_coverage_amount?: number | null;
  coi_on_file?: boolean;
  workers_comp_expiry?: string | null;
  bonded?: boolean;
  bond_amount?: number | null;
}

export interface GCUpdate {
  company_name?: string;
  gc_code?: string;
  license_number?: string | null;
  trade_type?: GCTradeType;
  phone?: string | null;
  email?: string | null;
  website?: string | null;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  insurance_info?: string | null;
  notes?: string | null;
  coi_carrier?: string | null;
  coi_policy_number?: string | null;
  coi_expiry_date?: string | null;
  coi_coverage_amount?: number | null;
  coi_on_file?: boolean;
  workers_comp_expiry?: string | null;
  bonded?: boolean;
  bond_amount?: number | null;
}


// ══════════════════════════════════════════════════════════════════
// ENTITY CONTACTS (polymorphic — customers, GCs, suppliers)
// ══════════════════════════════════════════════════════════════════

export type EntityType = 'customer' | 'general_contractor' | 'supplier';

export interface EntityContactResponse {
  id: number;
  entity_type: EntityType;
  entity_id: number;
  first_name: string;
  last_name: string;
  role: string;
  phone: string;
  email: string | null;
  is_primary: boolean;
  notes: string | null;
  is_active: boolean;
  created_at: string | null;
  updated_at: string | null;
}

export interface EntityContactCreate {
  first_name: string;
  last_name: string;
  role: string;
  phone: string;
  email?: string | null;
  is_primary?: boolean;
  notes?: string | null;
}

export interface EntityContactUpdate {
  first_name?: string;
  last_name?: string;
  role?: string;
  phone?: string;
  email?: string | null;
  is_primary?: boolean;
  notes?: string | null;
}

export interface DirectoryContactResult {
  id: number;
  first_name: string;
  last_name: string;
  role: string;
  phone: string;
  email: string | null;
  entity_type: EntityType;
  entity_id: number;
  entity_name: string;
}


// ══════════════════════════════════════════════════════════════════
// JOB ↔ CUSTOMER / GC LINKING
// ══════════════════════════════════════════════════════════════════

export type CustomerContactRole =
  | 'owner'
  | 'property_manager'
  | 'tenant'
  | 'site_contact'
  | 'billing'
  | 'other';

export type GCRelationship = 'they_are_gc' | 'we_hired_them';

export interface JobCustomerResponse {
  id: number;
  job_id: number;
  customer_id: number;
  customer_name: string;
  company_name: string | null;
  phone: string | null;
  email: string | null;
  contact_role: CustomerContactRole;
  is_primary: boolean;
  notes: string | null;
  created_at: string | null;
}

export interface JobCustomerCreate {
  customer_id: number;
  contact_role?: CustomerContactRole;
  is_primary?: boolean;
  notes?: string | null;
}

export interface JobGCResponse {
  id: number;
  job_id: number;
  gc_id: number;
  company_name: string;
  gc_code: string;
  trade_type: GCTradeType;
  phone: string | null;
  email: string | null;
  relationship: GCRelationship;
  contract_amount: number | null;
  contract_number: string | null;
  is_primary: boolean;
  notes: string | null;
  created_at: string | null;
}

export interface JobGCCreate {
  gc_id: number;
  relationship: GCRelationship;
  contract_amount?: number | null;
  contract_number?: string | null;
  is_primary?: boolean;
  notes?: string | null;
}

/** Job linked to a customer — used on the Customer Detail "Jobs" tab (reverse of JobCustomerResponse) */
export interface CustomerJobLink {
  id: number;
  job_id: number;
  customer_id: number;
  job_name: string;
  job_status: string;
  contact_role: CustomerContactRole;
  is_primary: boolean;
  notes: string | null;
  created_at: string | null;
}

/** Job linked to a GC — used on the Contractor Detail "Jobs" tab (reverse of JobGCResponse) */
export interface GCJobLink {
  id: number;
  job_id: number;
  gc_id: number;
  job_name: string;
  job_status: string;
  relationship: GCRelationship;
  contract_amount: number | null;
  contract_number: string | null;
  is_primary: boolean;
  notes: string | null;
  created_at: string | null;
}
