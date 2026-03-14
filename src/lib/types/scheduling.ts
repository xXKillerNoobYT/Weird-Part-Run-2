/**
 * Scheduling types — default schedules, exceptions/time off, dispatch,
 * subcontractors, calendar, shift patterns, weekly availability, dispatch templates.
 */

// ══════════════════════════════════════════════════════════════════
// SCHEDULING — DEFAULT SCHEDULES
// ══════════════════════════════════════════════════════════════════

export interface DefaultScheduleDay {
  day_of_week: number; // 0=Sunday, 1=Monday, ...
  start_time: string;  // "07:00"
  end_time: string;    // "15:30"
  lunch_start?: string | null;
  lunch_end?: string | null;
  is_working_day: boolean;
  notes: string | null;
}

export interface DefaultScheduleResponse {
  id: number;
  user_id: number;
  day_of_week: number;
  start_time: string;
  end_time: string;
  lunch_start: string | null;
  lunch_end: string | null;
  is_working_day: boolean;
  notes: string | null;
}

export interface DefaultScheduleCreate {
  days: DefaultScheduleDay[];
}


// ══════════════════════════════════════════════════════════════════
// SCHEDULING — SCHEDULE EXCEPTIONS (TIME OFF)
// ══════════════════════════════════════════════════════════════════

export type ExceptionType =
  | 'time_off'
  | 'sick'
  | 'vacation'
  | 'holiday'
  | 'modified_hours'
  | 'unpaid_leave'
  | 'jury_duty'
  | 'bereavement';

export interface ScheduleExceptionResponse {
  id: number;
  user_id: number;
  user_name?: string;
  exception_date: string;
  exception_type: ExceptionType;
  start_time: string | null;
  end_time: string | null;
  lunch_start: string | null;
  lunch_end: string | null;
  is_approved: boolean;
  approved_by: number | null;
  approved_by_name?: string;
  reason: string | null;
  notes: string | null;
  created_at: string | null;
}

export interface ScheduleExceptionCreate {
  exception_date: string;
  exception_type: ExceptionType;
  start_time?: string | null;
  end_time?: string | null;
  lunch_start?: string | null;
  lunch_end?: string | null;
  reason?: string | null;
  notes?: string | null;
}

export interface ScheduleExceptionUpdate {
  exception_date?: string;
  exception_type?: ExceptionType;
  start_time?: string | null;
  end_time?: string | null;
  lunch_start?: string | null;
  lunch_end?: string | null;
  reason?: string | null;
  notes?: string | null;
}


// ══════════════════════════════════════════════════════════════════
// SCHEDULING — DISPATCH
// ══════════════════════════════════════════════════════════════════

export type DispatchRoleOnJob = 'lead' | 'worker' | 'apprentice' | 'helper' | 'supervisor';
export type DispatchStatus =
  | 'scheduled'
  | 'confirmed'
  | 'on_site'
  | 'completed'
  | 'no_show'
  | 'cancelled';

export interface DispatchResponse {
  id: number;
  job_id: number;
  job_name?: string;
  user_id: number;
  user_name?: string;
  dispatch_date: string;
  shift_start: string | null;
  shift_end: string | null;
  lunch_start: string | null;
  lunch_end: string | null;
  role_on_job: DispatchRoleOnJob;
  status: DispatchStatus;
  dispatched_by: number | null;
  dispatched_by_name?: string;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface DispatchCreate {
  job_id: number;
  user_id: number;
  dispatch_date: string;
  shift_start?: string | null;
  shift_end?: string | null;
  lunch_start?: string | null;
  lunch_end?: string | null;
  role_on_job?: DispatchRoleOnJob;
  notes?: string | null;
}

export interface DispatchUpdate {
  dispatch_date?: string | null;
  shift_start?: string | null;
  shift_end?: string | null;
  lunch_start?: string | null;
  lunch_end?: string | null;
  role_on_job?: DispatchRoleOnJob;
  notes?: string | null;
}

export interface BulkDispatchCreate {
  job_id: number;
  user_ids: number[];
  dispatch_date: string;
  shift_start?: string | null;
  shift_end?: string | null;
  lunch_start?: string | null;
  lunch_end?: string | null;
  role_on_job?: DispatchRoleOnJob;
  notes?: string | null;
}

export interface BulkDispatchResult {
  created: Array<{ id: number; user_id: number; conflicts: ScheduleConflict[] }>;
  failed: Array<{ user_id: number; error: string }>;
}

export interface TeamDispatchCreate {
  job_id: number;
  team_id: number;
  dispatch_date: string;
  shift_start?: string | null;
  shift_end?: string | null;
  lunch_start?: string | null;
  lunch_end?: string | null;
  role_on_job?: DispatchRoleOnJob;
  notes?: string | null;
}

export interface TeamDispatchResult {
  team_id: number;
  team_size: number;
  created: Array<{ id: number; user_id: number; conflicts: ScheduleConflict[] }>;
  failed: Array<{ user_id: number; error: string }>;
}

export interface ScheduleConflict {
  conflict_type: string;
  description: string;
  date?: string;
  related_job_id?: number | null;
  related_job_name?: string | null;
  shift_start?: string | null;
  shift_end?: string | null;
  role_on_job?: string | null;
}

export interface DailyDispatchView {
  date: string;
  dispatches: DispatchResponse[];
  available_employees: Array<{
    id: number;
    display_name: string;
    hats: string[];
  }>;
}


// ══════════════════════════════════════════════════════════════════
// SCHEDULING — SUBCONTRACTOR SCHEDULES
// ══════════════════════════════════════════════════════════════════

export type SubScheduleStatus =
  | 'scheduled'
  | 'confirmed'
  | 'on_site'
  | 'completed'
  | 'cancelled'
  | 'no_show';

export interface SubScheduleResponse {
  id: number;
  job_id: number;
  job_name?: string;
  gc_id: number;
  gc_name?: string;
  scheduled_date: string;
  arrival_time: string | null;
  departure_time: string | null;
  work_description: string | null;
  status: SubScheduleStatus;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface SubScheduleCreate {
  job_id: number;
  gc_id: number;
  scheduled_date: string;
  arrival_time?: string | null;
  departure_time?: string | null;
  work_description?: string | null;
  notes?: string | null;
}

export interface SubScheduleUpdate {
  scheduled_date?: string;
  arrival_time?: string | null;
  departure_time?: string | null;
  work_description?: string | null;
  status?: SubScheduleStatus;
  notes?: string | null;
}


// ══════════════════════════════════════════════════════════════════
// SCHEDULING — CALENDAR (UNIFIED VIEW)
// ══════════════════════════════════════════════════════════════════

export type CalendarEntryType = 'dispatch' | 'time_off' | 'sub_schedule';

export interface CalendarEntry {
  reference_id: number | null;
  date: string;
  entry_type: CalendarEntryType;
  user_id: number | null;
  user_name: string | null;
  job_id: number | null;
  job_name: string | null;
  gc_id: number | null;
  gc_name: string | null;
  status: string;
  role_on_job?: string | null;
  label: string;
}

export interface CalendarData {
  date_from: string;
  date_to: string;
  entries: CalendarEntry[];
}


// ── Dispatch Templates ──────────────────────────────────────────

export interface DispatchTemplateMember {
  user_id: number;
  role_on_job?: string;
}

export interface DispatchTemplateMemberResponse {
  user_id: number;
  user_name?: string;
  role_on_job: string;
}

export interface DispatchTemplateCreate {
  name: string;
  job_id: number;
  shift_start?: string;
  shift_end?: string;
  lunch_start?: string;
  lunch_end?: string;
  role_on_job?: string;
  days_of_week?: number;
  members?: DispatchTemplateMember[];
  notes?: string;
}

export interface DispatchTemplateUpdate {
  name?: string;
  job_id?: number;
  shift_start?: string;
  shift_end?: string;
  lunch_start?: string;
  lunch_end?: string;
  role_on_job?: string;
  days_of_week?: number;
  members?: DispatchTemplateMember[];
  notes?: string;
}

export interface DispatchTemplateResponse {
  id: number;
  name: string;
  job_id: number;
  job_name?: string;
  shift_start?: string;
  shift_end?: string;
  lunch_start?: string;
  lunch_end?: string;
  role_on_job: string;
  days_of_week: number;
  days_labels: string[];
  members: DispatchTemplateMemberResponse[];
  notes?: string;
  is_active: boolean;
  created_at?: string;
}

export interface DispatchTemplateApply {
  date_from: string;
  date_to: string;
  skip_conflicts?: boolean;
}

// ── Shift Patterns ──────────────────────────────────────────────

export interface ShiftPatternDayCreate {
  day_of_week: number;
  start_time: string;
  end_time: string;
  lunch_start?: string | null;
  lunch_end?: string | null;
  is_working_day: boolean;
}

export interface ShiftPatternCreate {
  name: string;
  description?: string;
  days: ShiftPatternDayCreate[];
}

export interface ShiftPatternUpdate {
  name?: string;
  description?: string;
  days?: ShiftPatternDayCreate[];
}

export interface ShiftPatternDayResponse {
  id: number;
  day_of_week: number;
  start_time: string;
  end_time: string;
  lunch_start: string | null;
  lunch_end: string | null;
  is_working_day: boolean;
}

export interface ShiftPatternResponse {
  id: number;
  name: string;
  description?: string;
  is_active: boolean;
  days: ShiftPatternDayResponse[];
  created_at?: string;
}

// ── Weekly Availability ──────────────────────────────────────────

export interface AvailabilityDay {
  date: string;
  dispatches: number;
  time_off: boolean;
  available: boolean;
}

export interface EmployeeAvailability {
  user_id: number;
  user_name: string;
  days: AvailabilityDay[];
}
