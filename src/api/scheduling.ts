/**
 * Scheduling API functions — default schedules, time off, dispatch,
 * subcontractor scheduling, and unified calendar.
 *
 * All functions follow: call apiClient -> unwrap ApiResponse -> return typed data.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type {
  ApiResponse,
  // Default Schedules
  DefaultScheduleResponse,
  DefaultScheduleCreate,
  // Time Off (Schedule Exceptions)
  ScheduleExceptionResponse,
  ScheduleExceptionCreate,
  ScheduleExceptionUpdate,
  // Dispatch
  DispatchResponse,
  DispatchCreate,
  DispatchUpdate,
  BulkDispatchCreate,
  BulkDispatchResult,
  TeamDispatchCreate,
  TeamDispatchResult,
  ScheduleConflict,
  DailyDispatchView,
  // Subcontractor
  SubScheduleResponse,
  SubScheduleCreate,
  SubScheduleUpdate,
  // Calendar
  CalendarData,
  // Dispatch Templates
  DispatchTemplateCreate,
  DispatchTemplateUpdate,
  DispatchTemplateResponse,
  DispatchTemplateApply,
  // Shift Patterns
  ShiftPatternCreate,
  ShiftPatternUpdate,
  ShiftPatternResponse,
  // Weekly Availability
  EmployeeAvailability,
} from '../lib/types';


// =================================================================
// DEFAULT SCHEDULES
// =================================================================

/** Get the 7-day default schedule for an employee */
export async function getDefaultSchedule(
  userId: number,
): Promise<DefaultScheduleResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DefaultScheduleResponse[]>>(
        `/scheduling/schedules/${userId}/default`,
      );
      return data.data!;
    },
    async () => {
      const { getMySchedule } = await import('../local/services/scheduling-service');
      return await getMySchedule(userId) as unknown as DefaultScheduleResponse[];
    },
  );
}

/** Replace the full 7-day default schedule for an employee */
export async function setDefaultSchedule(
  userId: number,
  schedule: DefaultScheduleCreate,
): Promise<DefaultScheduleResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<DefaultScheduleResponse[]>>(
        `/scheduling/schedules/${userId}/default`,
        schedule,
      );
      return data.data!;
    },
    async () => { throw new Error('Schedule management requires the shop server.'); },
  );
}

/** Initialize a standard Mon-Fri 07:00-15:30 schedule */
export async function initDefaultSchedule(
  userId: number,
): Promise<DefaultScheduleResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<DefaultScheduleResponse[]>>(
        `/scheduling/schedules/${userId}/default/init`,
      );
      return data.data!;
    },
    async () => { throw new Error('Schedule management requires the shop server.'); },
  );
}


// =================================================================
// TIME OFF (SCHEDULE EXCEPTIONS)
// =================================================================

/** Get all pending (unapproved) time-off requests */
export async function getPendingTimeOff(
  limit = 100,
): Promise<ScheduleExceptionResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ScheduleExceptionResponse[]>>(
        '/scheduling/time-off/pending',
        { params: { limit } },
      );
      return data.data!;
    },
    async () => [] as unknown as ScheduleExceptionResponse[],
  );
}

/** Get time-off requests for a specific user */
export async function getUserTimeOff(
  userId: number,
  dateFrom?: string,
  dateTo?: string,
): Promise<ScheduleExceptionResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ScheduleExceptionResponse[]>>(
        `/scheduling/time-off/user/${userId}`,
        { params: { date_from: dateFrom, date_to: dateTo } },
      );
      return data.data!;
    },
    async () => {
      const { getMyTimeOff } = await import('../local/services/scheduling-service');
      return await getMyTimeOff(userId) as unknown as ScheduleExceptionResponse[];
    },
  );
}

/** Submit a time-off request for the current user */
export async function requestTimeOff(
  request: ScheduleExceptionCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        '/scheduling/time-off',
        request,
      );
      return data.data!;
    },
    async () => { throw new Error('Time-off requests require the shop server.'); },
  );
}

/** Submit a time-off request on behalf of another user (manager) */
export async function requestTimeOffForUser(
  userId: number,
  request: ScheduleExceptionCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/scheduling/time-off/${userId}`,
        request,
      );
      return data.data!;
    },
    async () => { throw new Error('Time-off requests require the shop server.'); },
  );
}

/** Update a time-off request */
export async function updateTimeOff(
  exceptionId: number,
  updates: ScheduleExceptionUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/scheduling/time-off/${exceptionId}`,
        updates,
      );
      return data.data!;
    },
    async () => { throw new Error('Time-off management requires the shop server.'); },
  );
}

/** Approve a time-off request */
export async function approveTimeOff(
  exceptionId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<{ id: number }>>(
        `/scheduling/time-off/${exceptionId}/approve`,
      );
      return data.data!;
    },
    async () => { throw new Error('Time-off approvals require the shop server.'); },
  );
}

/** Deny (delete) a time-off request */
export async function denyTimeOff(
  exceptionId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<{ id: number }>>(
        `/scheduling/time-off/${exceptionId}/deny`,
      );
      return data.data!;
    },
    async () => { throw new Error('Time-off management requires the shop server.'); },
  );
}

/** Delete a time-off request entirely */
export async function deleteTimeOff(
  exceptionId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
        `/scheduling/time-off/${exceptionId}`,
      );
      return data.data!;
    },
    async () => { throw new Error('Time-off management requires the shop server.'); },
  );
}


// =================================================================
// DISPATCH
// =================================================================

/** Get daily dispatch view — dispatches and available employees for a date */
export async function getDailyDispatch(
  date: string,
): Promise<DailyDispatchView> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DailyDispatchView>>(
        '/scheduling/dispatch/daily',
        { params: { date } },
      );
      return data.data!;
    },
    async () => {
      const { getDispatchForDate } = await import('../local/services/scheduling-service');
      const assignments = await getDispatchForDate(date);
      // Local returns flat assignments; wrap in DailyDispatchView shape
      return { date, dispatches: assignments, available_employees: [] } as unknown as DailyDispatchView;
    },
  );
}

/** Check for scheduling conflicts without creating a dispatch */
export async function checkDispatchConflicts(
  userId: number,
  date: string,
): Promise<ScheduleConflict[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ScheduleConflict[]>>(
        '/scheduling/dispatch/conflicts',
        { params: { user_id: userId, date } },
      );
      return data.data!;
    },
    async () => [] as ScheduleConflict[],
  );
}

/** Get dispatches for a user within a date range */
export async function getUserDispatches(
  userId: number,
  dateFrom: string,
  dateTo: string,
): Promise<DispatchResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DispatchResponse[]>>(
        `/scheduling/dispatch/user/${userId}`,
        { params: { date_from: dateFrom, date_to: dateTo } },
      );
      return data.data!;
    },
    async () => {
      const { getMyDispatch } = await import('../local/services/scheduling-service');
      return await getMyDispatch(userId, dateFrom, dateTo) as unknown as DispatchResponse[];
    },
  );
}

/** Get dispatches for a job, optionally within a date range */
export async function getJobDispatches(
  jobId: number,
  dateFrom?: string,
  dateTo?: string,
): Promise<DispatchResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DispatchResponse[]>>(
        `/scheduling/dispatch/job/${jobId}`,
        { params: { date_from: dateFrom, date_to: dateTo } },
      );
      return data.data!;
    },
    async () => [] as unknown as DispatchResponse[],
  );
}

/** Dispatch a single employee to a job */
export async function dispatchEmployee(
  dispatch: DispatchCreate,
): Promise<{ id: number; conflicts: ScheduleConflict[] }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<
        ApiResponse<{ id: number; conflicts: ScheduleConflict[] }>
      >('/scheduling/dispatch', dispatch);
      return data.data!;
    },
    async () => { throw new Error('Dispatch management requires the shop server.'); },
  );
}

/** Dispatch multiple employees to the same job/date */
export async function bulkDispatch(
  dispatch: BulkDispatchCreate,
): Promise<BulkDispatchResult> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BulkDispatchResult>>(
        '/scheduling/dispatch/bulk',
        dispatch,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch management requires the shop server.'); },
  );
}

/** Dispatch all members of an employee team to a job/date */
export async function dispatchTeam(
  dispatch: TeamDispatchCreate,
): Promise<TeamDispatchResult> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TeamDispatchResult>>(
        '/scheduling/dispatch/team',
        dispatch,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch management requires the shop server.'); },
  );
}

/** Update a dispatch assignment */
export async function updateDispatch(
  dispatchId: number,
  updates: DispatchUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/scheduling/dispatch/${dispatchId}`,
        updates,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch management requires the shop server.'); },
  );
}

/** Quick status update for a dispatch */
export async function updateDispatchStatus(
  dispatchId: number,
  status: string,
): Promise<{ id: number; status: string }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<{ id: number; status: string }>>(
        `/scheduling/dispatch/${dispatchId}/status`,
        null,
        { params: { status } },
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch management requires the shop server.'); },
  );
}

/** Cancel a dispatch assignment */
export async function cancelDispatch(
  dispatchId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<{ id: number }>>(
        `/scheduling/dispatch/${dispatchId}/cancel`,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch management requires the shop server.'); },
  );
}


// =================================================================
// SUBCONTRACTOR SCHEDULING
// =================================================================

/** Get subcontractor schedules for a job */
export async function getJobSubSchedules(
  jobId: number,
  dateFrom?: string,
  dateTo?: string,
): Promise<SubScheduleResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SubScheduleResponse[]>>(
        `/scheduling/subcontractors/job/${jobId}`,
        { params: { date_from: dateFrom, date_to: dateTo } },
      );
      return data.data!;
    },
    async () => [] as unknown as SubScheduleResponse[],
  );
}

/** Schedule a subcontractor visit on a job */
export async function scheduleSubcontractor(
  schedule: SubScheduleCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        '/scheduling/subcontractors',
        schedule,
      );
      return data.data!;
    },
    async () => { throw new Error('Subcontractor scheduling requires the shop server.'); },
  );
}

/** Update a subcontractor schedule entry */
export async function updateSubSchedule(
  scheduleId: number,
  updates: SubScheduleUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/scheduling/subcontractors/${scheduleId}`,
        updates,
      );
      return data.data!;
    },
    async () => { throw new Error('Subcontractor scheduling requires the shop server.'); },
  );
}

/** Cancel a subcontractor schedule entry */
export async function cancelSubSchedule(
  scheduleId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<{ id: number }>>(
        `/scheduling/subcontractors/${scheduleId}/cancel`,
      );
      return data.data!;
    },
    async () => { throw new Error('Subcontractor scheduling requires the shop server.'); },
  );
}


// =================================================================
// CALENDAR (UNIFIED VIEW)
// =================================================================

/** Assemble unified calendar data for a date range */
export async function getCalendarData(
  dateFrom: string,
  dateTo: string,
): Promise<CalendarData> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CalendarData>>(
        '/scheduling/calendar',
        { params: { date_from: dateFrom, date_to: dateTo } },
      );
      return data.data!;
    },
    async () => {
      const { getCalendarData: local } = await import('../local/services/scheduling-service');
      return await local(dateFrom, dateTo) as unknown as CalendarData;
    },
  );
}


// =================================================================
// DISPATCH TEMPLATES
// =================================================================

/** List all dispatch templates */
export async function listDispatchTemplates(
  activeOnly = true,
): Promise<DispatchTemplateResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DispatchTemplateResponse[]>>(
        '/scheduling/templates',
        { params: { active_only: activeOnly } },
      );
      return data.data!;
    },
    async () => [] as unknown as DispatchTemplateResponse[],
  );
}

/** Get a single dispatch template */
export async function getDispatchTemplate(
  templateId: number,
): Promise<DispatchTemplateResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DispatchTemplateResponse>>(
        `/scheduling/templates/${templateId}`,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch templates require the shop server.'); },
  );
}

/** Create a dispatch template */
export async function createDispatchTemplate(
  template: DispatchTemplateCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        '/scheduling/templates',
        template,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch templates require the shop server.'); },
  );
}

/** Update a dispatch template */
export async function updateDispatchTemplate(
  templateId: number,
  updates: DispatchTemplateUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/scheduling/templates/${templateId}`,
        updates,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch templates require the shop server.'); },
  );
}

/** Delete a dispatch template */
export async function deleteDispatchTemplate(
  templateId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
        `/scheduling/templates/${templateId}`,
      );
      return data.data!;
    },
    async () => { throw new Error('Dispatch templates require the shop server.'); },
  );
}

/** Apply a template to generate dispatches for a date range */
export async function applyDispatchTemplate(
  templateId: number,
  apply: DispatchTemplateApply,
): Promise<{ created: number; skipped: number; conflicts: ScheduleConflict[] }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<
        ApiResponse<{ created: number; skipped: number; conflicts: ScheduleConflict[] }>
      >(`/scheduling/templates/${templateId}/apply`, apply);
      return data.data!;
    },
    async () => { throw new Error('Dispatch templates require the shop server.'); },
  );
}


// =================================================================
// SHIFT PATTERNS
// =================================================================

/** List all shift patterns */
export async function listShiftPatterns(
  activeOnly = true,
): Promise<ShiftPatternResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ShiftPatternResponse[]>>(
        '/scheduling/shift-patterns',
        { params: { active_only: activeOnly } },
      );
      return data.data!;
    },
    async () => [] as unknown as ShiftPatternResponse[],
  );
}

/** Get a single shift pattern */
export async function getShiftPattern(
  patternId: number,
): Promise<ShiftPatternResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ShiftPatternResponse>>(
        `/scheduling/shift-patterns/${patternId}`,
      );
      return data.data!;
    },
    async () => { throw new Error('Shift patterns require the shop server.'); },
  );
}

/** Create a shift pattern */
export async function createShiftPattern(
  pattern: ShiftPatternCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        '/scheduling/shift-patterns',
        pattern,
      );
      return data.data!;
    },
    async () => { throw new Error('Shift patterns require the shop server.'); },
  );
}

/** Update a shift pattern */
export async function updateShiftPattern(
  patternId: number,
  updates: ShiftPatternUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/scheduling/shift-patterns/${patternId}`,
        updates,
      );
      return data.data!;
    },
    async () => { throw new Error('Shift patterns require the shop server.'); },
  );
}

/** Delete a shift pattern */
export async function deleteShiftPattern(
  patternId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
        `/scheduling/shift-patterns/${patternId}`,
      );
      return data.data!;
    },
    async () => { throw new Error('Shift patterns require the shop server.'); },
  );
}

/** Apply a shift pattern to a user's default schedule */
export async function applyShiftPatternToUser(
  patternId: number,
  userId: number,
): Promise<{ user_id: number; pattern_id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<
        ApiResponse<{ user_id: number; pattern_id: number }>
      >(`/scheduling/shift-patterns/${patternId}/apply/${userId}`);
      return data.data!;
    },
    async () => { throw new Error('Shift patterns require the shop server.'); },
  );
}


// =================================================================
// WEEKLY AVAILABILITY
// =================================================================

/** Get weekly employee availability for a date range */
export async function getWeeklyAvailability(
  dateFrom: string,
  dateTo: string,
): Promise<EmployeeAvailability[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EmployeeAvailability[]>>(
        '/scheduling/availability/weekly',
        { params: { date_from: dateFrom, date_to: dateTo } },
      );
      return data.data!;
    },
    async () => [] as unknown as EmployeeAvailability[],
  );
}


// =================================================================
// PTO POLICIES & BALANCES
// =================================================================

export interface PtoPolicy {
  id: number;
  user_id: number;
  policy_name: string;
  accrual_rate: number;
  accrual_period: 'weekly' | 'biweekly' | 'monthly';
  max_balance: number | null;
  carryover_limit: number | null;
  start_date: string;
  is_active: boolean;
}

export interface PtoTransaction {
  id: number;
  user_id: number;
  transaction_type: 'accrual' | 'usage' | 'adjustment' | 'carryover' | 'forfeit';
  hours: number;
  balance_after: number;
  reference_id: number | null;
  reference_type: string | null;
  note: string | null;
  effective_date: string;
  created_by: number | null;
  created_at: string;
}

export interface PtoBalance {
  user_id: number;
  user_name: string;
  current_balance: number;
  accrued_ytd: number;
  used_ytd: number;
  policy: PtoPolicy | null;
  recent_transactions: PtoTransaction[];
}

export interface PtoBalanceSummary {
  user_id: number;
  user_name: string;
  current_balance: number;
  policy_name: string;
  accrual_rate: number;
  accrual_period: string;
  max_balance: number | null;
}

/** Get PTO balance + transactions for a specific user */
export async function getPtoBalance(userId: number): Promise<PtoBalance> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PtoBalance>>(
        `/scheduling/pto/balance/${userId}`,
      );
      return data.data!;
    },
    async () => {
      const { getPtoBalance: local } = await import('../local/services/scheduling-service');
      return await local(userId) as unknown as PtoBalance;
    },
  );
}

/** Get all PTO balances (manager view) */
export async function getAllPtoBalances(): Promise<PtoBalanceSummary[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PtoBalanceSummary[]>>(
        '/scheduling/pto/balances',
      );
      return data.data!;
    },
    async () => [] as unknown as PtoBalanceSummary[],
  );
}

/** Create a PTO policy for a user */
export async function createPtoPolicy(body: {
  user_id: number;
  policy_name?: string;
  accrual_rate?: number;
  accrual_period?: 'weekly' | 'biweekly' | 'monthly';
  max_balance?: number | null;
  carryover_limit?: number | null;
  start_date: string;
}): Promise<PtoPolicy> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<PtoPolicy>>(
        '/scheduling/pto/policies',
        body,
      );
      return data.data!;
    },
    async () => { throw new Error('PTO policy management requires the shop server.'); },
  );
}

/** Update an existing PTO policy */
export async function updatePtoPolicy(
  policyId: number,
  body: Partial<{
    policy_name: string;
    accrual_rate: number;
    accrual_period: 'weekly' | 'biweekly' | 'monthly';
    max_balance: number | null;
    carryover_limit: number | null;
    is_active: boolean;
  }>,
): Promise<PtoPolicy> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PtoPolicy>>(
        `/scheduling/pto/policies/${policyId}`,
        body,
      );
      return data.data!;
    },
    async () => { throw new Error('PTO policy management requires the shop server.'); },
  );
}

/** Record a PTO transaction (adjustment, usage, etc.) */
export async function createPtoTransaction(body: {
  user_id: number;
  transaction_type: 'accrual' | 'usage' | 'adjustment' | 'carryover' | 'forfeit';
  hours: number;
  note?: string;
  effective_date: string;
  reference_id?: number;
  reference_type?: string;
}): Promise<PtoTransaction> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<PtoTransaction>>(
        '/scheduling/pto/transactions',
        body,
      );
      return data.data!;
    },
    async () => { throw new Error('PTO transactions require the shop server.'); },
  );
}

/** Run PTO accruals for all active policies */
export async function runPtoAccruals(): Promise<{
  processed: number;
  skipped: number;
  total_policies: number;
}> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<
        ApiResponse<{ processed: number; skipped: number; total_policies: number }>
      >('/scheduling/pto/run-accruals');
      return data.data!;
    },
    async () => { throw new Error('PTO accruals require the shop server.'); },
  );
}
