/**
 * Jobs & Labor types — jobs, bill rates, labor entries, clock-out questions, daily reports.
 */

// ═══════════════════════════════════════════════════════════════════
// JOBS MODULE (Phase 4)
// ═══════════════════════════════════════════════════════════════════

// ── Job Types ────────────────────────────────────────────────────

export type JobStatus =
  | 'pending' | 'active' | 'on_hold'
  | 'completed' | 'cancelled'
  | 'continuous_maintenance' | 'on_call';
export type JobPriority = 'low' | 'normal' | 'high' | 'urgent';
export type JobType = 'service' | 'new_construction' | 'remodel' | 'maintenance' | 'emergency';
export type OnCallType = 'on_call' | 'warranty';

/** Display labels for on_call sub-types */
export const ON_CALL_TYPE_LABELS: Record<OnCallType, string> = {
  on_call: 'On Call',
  warranty: 'Warranty',
};

/** Human-readable display labels for job statuses */
export const JOB_STATUS_LABELS: Record<JobStatus, string> = {
  pending: 'Pending',
  active: 'Active',
  on_hold: 'On Hold',
  completed: 'Completed',
  cancelled: 'Cancelled',
  continuous_maintenance: 'Cont. Maint.',
  on_call: 'On Call / Warranty',
};

// ── Bill Rate Types ──────────────────────────────────────────────

export interface BillRateType {
  id: number;
  name: string;
  description?: string | null;
  sort_order: number;
  is_active: boolean;
  created_at?: string | null;
}

export interface BillRateTypeCreate {
  name: string;
  description?: string | null;
}

export interface BillRateTypeUpdate {
  name?: string;
  description?: string | null;
  is_active?: boolean;
}
export type LaborStatus = 'clocked_in' | 'clocked_out' | 'edited' | 'approved';
export type ReportStatus = 'generated' | 'reviewed' | 'locked';

export interface JobCreate {
  job_number: string;
  job_name: string;
  customer_name: string;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  state?: string;
  zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  status?: JobStatus;
  priority?: JobPriority;
  job_type?: JobType;
  bill_rate_type_id?: number;
  lead_user_id?: number;
  start_date?: string;
  due_date?: string;
  notes?: string;
  on_call_type?: OnCallType;
  warranty_start_date?: string;
  warranty_end_date?: string;
}

export interface JobUpdate {
  job_name?: string;
  customer_name?: string;
  status?: JobStatus;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  state?: string;
  zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  priority?: JobPriority;
  job_type?: JobType;
  bill_rate_type_id?: number;
  lead_user_id?: number;
  start_date?: string;
  due_date?: string;
  notes?: string;
  on_call_type?: OnCallType | null;
  warranty_start_date?: string | null;
  warranty_end_date?: string | null;
}

export interface JobTeamMember {
  id: number;
  job_id: number;
  user_id: number;
  display_name: string;
  email?: string | null;
  role: 'lead' | 'member';
  assigned_at: string;
  notes?: string | null;
}

export interface JobResponse {
  id: number;
  job_number: string;
  job_name: string;
  customer_name: string;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  gps_lat?: number | null;
  gps_lng?: number | null;
  status: JobStatus;
  priority: JobPriority;
  job_type: JobType;
  bill_rate_type_id?: number | null;
  bill_rate_type_name?: string | null;
  lead_user_id?: number | null;
  lead_user_name?: string | null;
  start_date?: string | null;
  due_date?: string | null;
  completed_date?: string | null;
  notes?: string | null;
  on_call_type?: OnCallType | null;
  warranty_start_date?: string | null;
  warranty_end_date?: string | null;
  warranty_days_remaining?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
  // Aggregated stats
  total_labor_hours?: number | null;
  total_parts_cost?: number | null;
  active_workers?: number | null;
  // Notebook task aggregation
  open_task_count: number;
  task_summary?: Record<string, number> | null;
}

export interface JobListItem {
  id: number;
  job_number: string;
  job_name: string;
  customer_name: string;
  address_line1?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  gps_lat?: number | null;
  gps_lng?: number | null;
  status: JobStatus;
  priority: JobPriority;
  job_type: JobType;
  bill_rate_type_name?: string | null;
  lead_user_name?: string | null;
  on_call_type?: OnCallType | null;
  warranty_end_date?: string | null;
  active_workers: number;
  total_labor_hours: number;
  total_parts_cost: number;
  open_task_count: number;
  created_at?: string | null;
}

// ── Labor Entry Types ────────────────────────────────────────────

export interface ClockInRequest {
  gps_lat?: number;
  gps_lng?: number;
}

export interface ClockOutResponseInput {
  question_id: number;
  answer_text?: string | null;
  answer_bool?: boolean | null;
}

export interface OneTimeAnswerInput {
  question_id: number;
  answer_text?: string | null;
}

export interface ClockOutRequest {
  labor_entry_id: number;
  gps_lat?: number;
  gps_lng?: number;
  drive_time_minutes?: number;
  notes?: string;
  responses: ClockOutResponseInput[];
  one_time_answers: OneTimeAnswerInput[];
}

export interface LaborEntryResponse {
  id: number;
  user_id: number;
  user_name?: string | null;
  job_id: number;
  job_name?: string | null;
  job_number?: string | null;
  clock_in: string;
  clock_out?: string | null;
  regular_hours?: number | null;
  overtime_hours?: number | null;
  drive_time_minutes: number;
  clock_in_gps_lat?: number | null;
  clock_in_gps_lng?: number | null;
  clock_out_gps_lat?: number | null;
  clock_out_gps_lng?: number | null;
  clock_in_photo_path?: string | null;
  clock_out_photo_path?: string | null;
  status: LaborStatus;
  notes?: string | null;
  created_at?: string | null;
}

export interface ActiveClockResponse {
  is_clocked_in: boolean;
  entry?: LaborEntryResponse | null;
}

// ── Clock-Out Questions ──────────────────────────────────────────

export type QuestionAnswerType = 'text' | 'yes_no' | 'photo';

export interface ClockOutQuestionResponse {
  id: number;
  question_text: string;
  answer_type: QuestionAnswerType;
  is_required: boolean;
  sort_order: number;
  is_active: boolean;
  created_at?: string | null;
}

export interface ClockOutQuestionCreate {
  question_text: string;
  answer_type?: QuestionAnswerType;
  is_required?: boolean;
  sort_order?: number;
}

// ── One-Time Questions ───────────────────────────────────────────

export type OneTimeQuestionStatus = 'pending' | 'answered' | 'expired' | 'cancelled';

export interface OneTimeQuestionResponse {
  id: number;
  job_id: number;
  target_user_id?: number | null;
  target_user_name?: string | null;
  question_text: string;
  answer_type: QuestionAnswerType;
  status: OneTimeQuestionStatus;
  created_by: number;
  created_by_name?: string | null;
  answered_by?: number | null;
  answer_text?: string | null;
  answer_photo_path?: string | null;
  created_at?: string | null;
  answered_at?: string | null;
}

export interface OneTimeQuestionCreate {
  question_text: string;
  answer_type?: QuestionAnswerType;
  target_user_id?: number | null;
}

// ── Clock-Out Bundle ─────────────────────────────────────────────

export interface ClockOutBundle {
  global_questions: ClockOutQuestionResponse[];
  one_time_questions: OneTimeQuestionResponse[];
}

// ── Job Parts ────────────────────────────────────────────────────

export interface JobPartConsumeRequest {
  part_id: number;
  qty_consumed: number;
  notes?: string;
}

export interface JobPartResponse {
  id: number;
  job_id: number;
  part_id: number;
  part_name?: string | null;
  part_code?: string | null;
  qty_consumed: number;
  qty_returned: number;
  unit_cost_at_consume?: number | null;
  unit_sell_at_consume?: number | null;
  consumed_by?: number | null;
  consumed_by_name?: string | null;
  consumed_at?: string | null;
  notes?: string | null;
}

// ── Daily Reports ────────────────────────────────────────────────

export interface DailyReportResponse {
  id: number;
  job_id: number;
  job_name?: string | null;
  job_number?: string | null;
  report_date: string;
  status: ReportStatus;
  generated_at?: string | null;
  reviewed_by?: number | null;
  reviewed_at?: string | null;
  // Summary fields extracted from report JSON
  worker_count: number;
  total_labor_hours: number;
  total_parts_cost: number;
  total_drive_time_minutes?: number;
}

export interface DailyReportFull {
  id: number;
  job_id: number;
  job_name?: string | null;
  job_number?: string | null;
  report_date: string;
  status: ReportStatus;
  generated_at?: string | null;
  report_data: ReportData;
}

// ── Report Data (the JSON blob structure) ────────────────────────

export interface ReportData {
  job_id: number;
  job_name: string;
  job_number: string;
  report_date: string;
  workers: ReportWorker[];
  parts_consumed: ReportPartConsumed[];
  deliveries?: ReportDelivery[];
  trip_legs?: ReportTripLeg[];
  vehicles_involved?: ReportVehicleInvolved[];
  summary: ReportSummary;
}

export interface ReportWorker {
  user_id: number;
  display_name: string;
  clock_in: string;
  clock_out?: string | null;
  regular_hours: number;
  overtime_hours: number;
  drive_time_minutes: number;
  clock_in_gps?: { lat: number; lng: number } | null;
  clock_out_gps?: { lat: number; lng: number } | null;
  clock_in_photo?: string | null;
  clock_out_photo?: string | null;
  responses: ReportQuestionAnswer[];
  one_time_responses: ReportOneTimeAnswer[];
}

export interface ReportQuestionAnswer {
  question: string;
  type: QuestionAnswerType;
  answer: string | boolean;
  photo?: string | null;
}

export interface ReportOneTimeAnswer {
  question: string;
  answer: string;
  photo?: string | null;
}

export interface ReportPartConsumed {
  part_name: string;
  part_code?: string | null;
  qty: number;
  unit_cost: number;
  total: number;
}

export interface ReportSummary {
  total_labor_hours: number;
  total_parts_cost: number;
  worker_count: number;
  total_delivery_items?: number;
  total_miles_driven?: number;
  total_billable_drive_minutes?: number;
  vehicles_involved_count?: number;
}

export interface ReportDelivery {
  vehicle_name: string;
  vehicle_number: string;
  part_name: string;
  part_code?: string | null;
  qty_delivered: number;
  delivered_by_name?: string | null;
  delivered_at?: string | null;
}

export interface ReportTripLeg {
  leg_type: string;
  from_label?: string | null;
  to_label?: string | null;
  miles?: number | null;
  drive_minutes?: number | null;
  is_billable: boolean;
  vehicle_name: string;
  vehicle_number: string;
  driver_name: string;
}

export interface ReportVehicleInvolved {
  vehicle_name: string;
  vehicle_number: string;
  drivers: string[];
  total_miles: number;
  delivered_items: number;
}
