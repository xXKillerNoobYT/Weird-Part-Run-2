/**
 * People types — certifications, wage history, employee notes, skills,
 * employees, teams, hats, permissions.
 */

import type { HatSummary } from './common';

// ═══════════════════════════════════════════════════════════════════
// Phase 8: People (Full)
// ═══════════════════════════════════════════════════════════════════

// ── Certifications ─────────────────────────────────────────────────

export type CertType =
  | 'journeyman' | 'apprentice' | 'master'
  | 'osha_10' | 'osha_30'
  | 'first_aid' | 'cpr'
  | 'forklift' | 'confined_space'
  | 'custom';

export interface CertificationResponse {
  id: number;
  user_id: number;
  cert_type: CertType;
  cert_name: string;
  issuing_authority: string | null;
  cert_number: string | null;
  issued_date: string | null;
  expiry_date: string | null;
  is_active: boolean;
  notes: string | null;
  document_path: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface CertificationCreate {
  cert_type: CertType;
  cert_name: string;
  issuing_authority?: string | null;
  cert_number?: string | null;
  issued_date?: string | null;
  expiry_date?: string | null;
  notes?: string | null;
}

export interface CertificationUpdate {
  cert_type?: CertType | null;
  cert_name?: string | null;
  issuing_authority?: string | null;
  cert_number?: string | null;
  issued_date?: string | null;
  expiry_date?: string | null;
  is_active?: boolean | null;
  notes?: string | null;
}

/** Expiring cert — includes user_name from the JOIN */
export interface ExpiringCertification extends CertificationResponse {
  user_name: string;
}

// ── Wage History ───────────────────────────────────────────────────

export type WageReason = 'hire' | 'raise' | 'promotion' | 'demotion' | 'adjustment' | 'correction';

export interface WageHistoryResponse {
  id: number;
  user_id: number;
  pay_rate: number;
  effective_date: string;
  reason: WageReason | null;
  changed_by: number | null;
  changed_by_name: string | null;
  created_at: string | null;
}

export interface WageHistoryCreate {
  pay_rate: number;
  effective_date: string;
  reason?: WageReason | null;
}

// ── Employee Notes ─────────────────────────────────────────────────

export type NoteType = 'general' | 'performance' | 'incident' | 'commendation' | 'training' | 'disciplinary';

export interface EmployeeNoteResponse {
  id: number;
  user_id: number;
  note_type: NoteType;
  title: string;
  body: string;
  is_private: boolean;
  created_by: number | null;
  created_by_name: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface EmployeeNoteCreate {
  note_type?: NoteType;
  title: string;
  body: string;
  is_private?: boolean;
}

export interface EmployeeNoteUpdate {
  note_type?: NoteType | null;
  title?: string | null;
  body?: string | null;
  is_private?: boolean | null;
}

// ── User Skills ────────────────────────────────────────────────────

export type Proficiency = 'beginner' | 'intermediate' | 'advanced' | 'expert';

export interface UserSkillResponse {
  id: number;
  user_id: number;
  skill_name: string;
  proficiency: Proficiency;
  years_experience: number | null;
  verified_by: number | null;
  verified_by_name: string | null;
  verified_at: string | null;
  created_at: string | null;
}

export interface UserSkillCreate {
  skill_name: string;
  proficiency?: Proficiency;
  years_experience?: number | null;
}

export interface UserSkillUpdate {
  skill_name?: string | null;
  proficiency?: Proficiency | null;
  years_experience?: number | null;
}

// ── Employees ──────────────────────────────────────────────────────

export type CertificationLevel = 'journeyman' | 'apprentice' | 'master';

export interface EmployeeListItem {
  id: number;
  display_name: string;
  email: string | null;
  phone: string | null;
  certification: CertificationLevel | null;
  hire_date: string | null;
  pay_rate: number | null;
  is_active: boolean;
  avatar_url: string | null;
  hat_names: string[];
  active_cert_count: number;
}

export interface EmployeeDetail {
  id: number;
  display_name: string;
  email: string | null;
  phone: string | null;
  certification: CertificationLevel | null;
  hire_date: string | null;
  pay_rate: number | null;
  is_active: boolean;
  avatar_url: string | null;
  emergency_contact_name: string | null;
  emergency_contact_phone: string | null;

  // Related collections
  hats: HatSummary[];
  permissions: string[];
  certifications: CertificationResponse[];
  wage_history: WageHistoryResponse[];
  notes: EmployeeNoteResponse[];
  skills: UserSkillResponse[];

  // Timestamps
  created_at: string | null;
  updated_at: string | null;
}

export interface EmployeeCreate {
  display_name: string;
  pin: string;
  email?: string | null;
  phone?: string | null;
  certification?: CertificationLevel | null;
  hire_date?: string | null;
  pay_rate?: number | null;
  hat_ids?: number[] | null;
  emergency_contact_name?: string | null;
  emergency_contact_phone?: string | null;
}

export interface EmployeeUpdate {
  display_name?: string | null;
  email?: string | null;
  phone?: string | null;
  certification?: CertificationLevel | null;
  hire_date?: string | null;
  pay_rate?: number | null;
  emergency_contact_name?: string | null;
  emergency_contact_phone?: string | null;
}

// ── Employee Teams ─────────────────────────────────────────────────

export type TeamMemberRole = 'lead' | 'member';

export interface EmployeeTeamListItem {
  id: number;
  name: string;
  description: string | null;
  lead_user_id: number | null;
  lead_name: string | null;
  is_active: boolean;
  member_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface TeamMemberItem {
  id: number;
  team_id: number;
  user_id: number;
  display_name: string;
  avatar_url: string | null;
  role: TeamMemberRole;
  user_is_active: boolean;
  joined_at: string | null;
}

export interface EmployeeTeamDetail {
  id: number;
  name: string;
  description: string | null;
  lead_user_id: number | null;
  lead_name: string | null;
  is_active: boolean;
  member_count: number;
  members: TeamMemberItem[];
  created_at: string | null;
  updated_at: string | null;
}

export interface EmployeeTeamCreate {
  name: string;
  description?: string | null;
  lead_user_id?: number | null;
}

export interface EmployeeTeamUpdate {
  name?: string | null;
  description?: string | null;
  lead_user_id?: number | null;
  is_active?: boolean | null;
}

export interface TeamMemberAdd {
  user_id: number;
  role?: TeamMemberRole;
}

// ── Hats (Roles) Management ────────────────────────────────────────

export interface HatDetailResponse {
  id: number;
  name: string;
  description: string | null;
  level: number;
  is_builtin: boolean;
  permissions: string[];
  user_count: number;
  created_at: string | null;
}

export interface HatCreate {
  name: string;
  description?: string | null;
  level?: number;
}

export interface HatUpdate {
  name?: string | null;
  description?: string | null;
  level?: number | null;
}

export interface PermissionAssignment {
  permission_keys: string[];
}

// ── Permission Matrix ──────────────────────────────────────────────

export interface PermissionMatrixRow {
  permission_key: string;
  domain: string;
  hat_values: Record<number, boolean>;  // hat_id → has_permission
}

export interface PermissionMatrixData {
  hats: Array<{ id: number; name: string; level: number }>;
  domains: Record<string, PermissionMatrixRow[]>;
}
