/**
 * Jobs API functions — job CRUD, labor clock in/out, questions,
 * parts consumption, and daily reports.
 *
 * All functions are wrapped with adaptedRequest() so Tauri builds
 * use local SQLite, while browser builds use HTTP.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type { ApiResponse } from '../lib/types';
import type {
  // Jobs
  JobCreate,
  JobUpdate,
  JobResponse,
  JobListItem,
  // Bill Rate Types
  BillRateType,
  BillRateTypeCreate,
  BillRateTypeUpdate,
  // Labor
  ClockInRequest,
  ClockOutRequest,
  LaborEntryResponse,
  ActiveClockResponse,
  // Questions
  ClockOutQuestionCreate,
  ClockOutQuestionResponse,
  OneTimeQuestionCreate,
  OneTimeQuestionResponse,
  ClockOutBundle,
  // Parts
  JobPartConsumeRequest,
  JobPartResponse,
  // Reports
  DailyReportResponse,
  DailyReportFull,
  StatusMessage,
  // Phase 7A: Preferences
  JobPreferenceResponse,
  JobPreferenceToggle,
  JobPreferencesSummary,
  // Phase 17: Explicit Preferred Suppliers
  ExplicitSupplierResponse,
  JobPreferredSuppliersUpdate,
  // Team
  JobTeamMember,
} from '../lib/types';


// =================================================================
// BILL RATE TYPES
// =================================================================

/** List bill rate types for dropdowns */
export async function getBillRateTypes(
  activeOnly: boolean = true
): Promise<BillRateType[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BillRateType[]>>(
        '/jobs/bill-rate-types',
        { params: { active_only: activeOnly } }
      );
      return data.data ?? [];
    },
    async () => {
      const { getBillRateTypes: local } = await import('../local/services/job-service');
      return await local(activeOnly) as unknown as BillRateType[];
    },
  );
}

/** Create a new bill rate type */
export async function createBillRateType(
  brt: BillRateTypeCreate
): Promise<BillRateType> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BillRateType>>(
        '/jobs/bill-rate-types',
        brt
      );
      return data.data!;
    },
    async () => {
      const { createBillRateType: local } = await import('../local/services/job-service');
      return await local(brt) as unknown as BillRateType;
    },
  );
}

/** Update a bill rate type */
export async function updateBillRateType(
  id: number,
  updates: BillRateTypeUpdate
): Promise<BillRateType> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<BillRateType>>(
        `/jobs/bill-rate-types/${id}`,
        updates
      );
      return data.data!;
    },
    async () => {
      const { updateBillRateType: local } = await import('../local/services/job-service');
      return await local(id, updates) as unknown as BillRateType;
    },
  );
}

/** Deactivate (soft-delete) a bill rate type */
export async function deleteBillRateType(id: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete<ApiResponse<StatusMessage>>(
        `/jobs/bill-rate-types/${id}`
      );
    },
    async () => {
      const { deleteBillRateType: local } = await import('../local/services/job-service');
      await local(id);
    },
  );
}


// =================================================================
// JOBS CRUD
// =================================================================

/** List active jobs with optional filters */
export async function getActiveJobs(params?: {
  search?: string;
  status?: string;
  job_type?: string;
  priority?: string;
  sort?: string;
  order?: string;
}): Promise<JobListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobListItem[]>>(
        '/jobs/active',
        { params }
      );
      return data.data ?? [];
    },
    async () => {
      const { getActiveJobs: local } = await import('../local/services/job-service');
      const result = await local(params);
      return result.items as unknown as JobListItem[];
    },
  );
}

/** Create a new job */
export async function createJob(job: JobCreate): Promise<JobResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<JobResponse>>(
        '/jobs',
        job
      );
      return data.data!;
    },
    async () => {
      const { createJob: local } = await import('../local/services/job-service');
      return await local(job, 0) as unknown as JobResponse;
    },
  );
}

/** Get full job detail */
export async function getJob(jobId: number): Promise<JobResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobResponse>>(
        `/jobs/${jobId}`
      );
      return data.data!;
    },
    async () => {
      const { getJob: local } = await import('../local/services/job-service');
      const job = await local(jobId);
      if (!job) throw new Error('Job not found');
      return job as unknown as JobResponse;
    },
  );
}

/** Update job information */
export async function updateJob(
  jobId: number,
  updates: JobUpdate
): Promise<JobResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<JobResponse>>(
        `/jobs/${jobId}`,
        updates
      );
      return data.data!;
    },
    async () => {
      const { updateJob: local } = await import('../local/services/job-service');
      const job = await local(jobId, updates);
      if (!job) throw new Error('Job not found');
      return job as unknown as JobResponse;
    },
  );
}

/** Change job status */
export async function updateJobStatus(
  jobId: number,
  status: string
): Promise<JobResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<JobResponse>>(
        `/jobs/${jobId}/status`,
        { status }
      );
      return data.data!;
    },
    async () => {
      const { updateJobStatus: local } = await import('../local/services/job-service');
      const job = await local(jobId, status);
      if (!job) throw new Error('Job not found');
      return job as unknown as JobResponse;
    },
  );
}


// =================================================================
// LABOR / CLOCK IN-OUT
// =================================================================

/** Clock in to a job */
export async function clockIn(
  jobId: number,
  request: ClockInRequest
): Promise<LaborEntryResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<LaborEntryResponse>>(
        `/jobs/${jobId}/clock-in`,
        request
      );
      return data.data!;
    },
    async () => {
      const { clockIn: local } = await import('../local/services/labor-service');
      return await local(0, { ...request, job_id: jobId }) as unknown as LaborEntryResponse;
    },
  );
}

/** Clock out from current job */
export async function clockOut(
  request: ClockOutRequest
): Promise<LaborEntryResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<LaborEntryResponse>>(
        '/jobs/clock-out',
        request
      );
      return data.data!;
    },
    async () => {
      const { clockOut: local } = await import('../local/services/labor-service');
      return await local(0, request as any) as unknown as LaborEntryResponse;
    },
  );
}

/** Get current user's active clock entry */
export async function getMyClock(): Promise<ActiveClockResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ActiveClockResponse>>(
        '/jobs/my-clock'
      );
      return data.data!;
    },
    async () => {
      const { getActiveClock } = await import('../local/services/labor-service');
      const clock = await getActiveClock(0);
      return (clock ?? { is_clocked_in: false }) as unknown as ActiveClockResponse;
    },
  );
}

/** Get labor entries for a specific job */
export async function getJobLabor(
  jobId: number,
  params?: { date_from?: string; date_to?: string }
): Promise<LaborEntryResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<LaborEntryResponse[]>>(
        `/jobs/${jobId}/labor`,
        { params }
      );
      return data.data ?? [];
    },
    async () => {
      const { getLaborForJob } = await import('../local/services/labor-service');
      return await getLaborForJob(jobId, params?.date_from, params?.date_to) as unknown as LaborEntryResponse[];
    },
  );
}

/** Get current user's labor history */
export async function getMyLabor(
  params?: { date_from?: string; date_to?: string }
): Promise<LaborEntryResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<LaborEntryResponse[]>>(
        '/jobs/my-labor',
        { params }
      );
      return data.data ?? [];
    },
    async () => {
      const { getLaborForUser } = await import('../local/services/labor-service');
      return await getLaborForUser(0, params?.date_from, params?.date_to) as unknown as LaborEntryResponse[];
    },
  );
}


// =================================================================
// PARTS CONSUMPTION
// =================================================================

/** List parts consumed on a job */
export async function getJobParts(jobId: number): Promise<JobPartResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobPartResponse[]>>(
        `/jobs/${jobId}/parts`
      );
      return data.data ?? [];
    },
    async () => {
      const { getJobParts: local } = await import('../local/services/job-service');
      return await local(jobId) as unknown as JobPartResponse[];
    },
  );
}

/** Record part consumption on a job */
export async function consumePart(
  jobId: number,
  request: JobPartConsumeRequest
): Promise<JobPartResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<JobPartResponse>>(
        `/jobs/${jobId}/parts/consume`,
        request
      );
      return data.data!;
    },
    async () => {
      const { consumePart: local } = await import('../local/services/job-service');
      return await local(jobId, request as any, 0) as unknown as JobPartResponse;
    },
  );
}


// =================================================================
// GLOBAL CLOCK-OUT QUESTIONS
// =================================================================

/** List global clock-out questions */
export async function getGlobalQuestions(
  activeOnly: boolean = true
): Promise<ClockOutQuestionResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ClockOutQuestionResponse[]>>(
        '/jobs/questions/global',
        { params: { active_only: activeOnly } }
      );
      return data.data ?? [];
    },
    async () => {
      const { getGlobalQuestions: local } = await import('../local/services/job-service');
      return await local(activeOnly) as unknown as ClockOutQuestionResponse[];
    },
  );
}

/** Create a new global question */
export async function createGlobalQuestion(
  question: ClockOutQuestionCreate
): Promise<ClockOutQuestionResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ClockOutQuestionResponse>>(
        '/jobs/questions/global',
        question
      );
      return data.data!;
    },
    async () => {
      const { createGlobalQuestion: local } = await import('../local/services/job-service');
      return await local(question as any, 0) as unknown as ClockOutQuestionResponse;
    },
  );
}

/** Update a global question */
export async function updateGlobalQuestion(
  questionId: number,
  question: ClockOutQuestionCreate
): Promise<ClockOutQuestionResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<ClockOutQuestionResponse>>(
        `/jobs/questions/global/${questionId}`,
        question
      );
      return data.data!;
    },
    async () => {
      const { updateGlobalQuestion: local } = await import('../local/services/job-service');
      return await local(questionId, question as any) as unknown as ClockOutQuestionResponse;
    },
  );
}

/** Reorder global questions */
export async function reorderGlobalQuestions(
  orderedIds: number[]
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.put<ApiResponse<StatusMessage>>(
        '/jobs/questions/global/reorder',
        { ordered_ids: orderedIds }
      );
    },
    async () => {
      const { reorderGlobalQuestions: local } = await import('../local/services/job-service');
      await local(orderedIds);
    },
  );
}

/** Deactivate (soft-delete) a global question */
export async function deactivateGlobalQuestion(
  questionId: number
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete<ApiResponse<StatusMessage>>(
        `/jobs/questions/global/${questionId}`
      );
    },
    async () => {
      const { deactivateGlobalQuestion: local } = await import('../local/services/job-service');
      await local(questionId);
    },
  );
}


// =================================================================
// ONE-TIME PER-JOB QUESTIONS
// =================================================================

/** List one-time questions for a job */
export async function getOneTimeQuestions(
  jobId: number,
  pendingOnly: boolean = false
): Promise<OneTimeQuestionResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<OneTimeQuestionResponse[]>>(
        `/jobs/${jobId}/questions/one-time`,
        { params: { pending_only: pendingOnly } }
      );
      return data.data ?? [];
    },
    async () => {
      const { getOneTimeQuestions: local } = await import('../local/services/job-service');
      return await local(jobId, pendingOnly) as unknown as OneTimeQuestionResponse[];
    },
  );
}

/** Create a one-time question for a job */
export async function createOneTimeQuestion(
  jobId: number,
  question: OneTimeQuestionCreate
): Promise<OneTimeQuestionResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<OneTimeQuestionResponse>>(
        `/jobs/${jobId}/questions/one-time`,
        question
      );
      return data.data!;
    },
    async () => {
      const { createOneTimeQuestion: local } = await import('../local/services/job-service');
      return await local(jobId, question as any, 0) as unknown as OneTimeQuestionResponse;
    },
  );
}

/** Answer a one-time question */
export async function answerOneTimeQuestion(
  questionId: number,
  answerText: string | null
): Promise<OneTimeQuestionResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<OneTimeQuestionResponse>>(
        `/jobs/questions/one-time/${questionId}/answer`,
        { answer_text: answerText }
      );
      return data.data!;
    },
    async () => {
      const { answerOneTimeQuestion: local } = await import('../local/services/job-service');
      return await local(questionId, answerText, 0) as unknown as OneTimeQuestionResponse;
    },
  );
}


// =================================================================
// CLOCK-OUT BUNDLE
// =================================================================

/** Get all questions for the clock-out flow */
export async function getClockOutBundle(
  jobId: number
): Promise<ClockOutBundle> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ClockOutBundle>>(
        `/jobs/${jobId}/clock-out-bundle`
      );
      return data.data!;
    },
    async () => {
      const { getClockOutBundle: local } = await import('../local/services/job-service');
      return await local(jobId) as unknown as ClockOutBundle;
    },
  );
}


// =================================================================
// DAILY REPORTS
// =================================================================

/** List all daily reports across jobs */
export async function getAllReports(
  params?: { date_from?: string; date_to?: string }
): Promise<DailyReportResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DailyReportResponse[]>>(
        '/jobs/reports/all',
        { params }
      );
      return data.data ?? [];
    },
    async () => {
      const { getAllReports: local } = await import('../local/services/job-service');
      return await local(params) as unknown as DailyReportResponse[];
    },
  );
}

/** List daily reports for a specific job */
export async function getJobReports(
  jobId: number
): Promise<DailyReportResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DailyReportResponse[]>>(
        `/jobs/${jobId}/reports`
      );
      return data.data ?? [];
    },
    async () => {
      const { getJobReports: local } = await import('../local/services/job-service');
      return await local(jobId) as unknown as DailyReportResponse[];
    },
  );
}

/** Get full daily report for a specific job and date */
export async function getReport(
  jobId: number,
  reportDate: string
): Promise<DailyReportFull> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DailyReportFull>>(
        `/jobs/${jobId}/reports/${reportDate}`
      );
      return data.data!;
    },
    async () => {
      const { getReport: local } = await import('../local/services/job-service');
      const report = await local(jobId, reportDate);
      if (!report) throw new Error('Report not found');
      return report as unknown as DailyReportFull;
    },
  );
}

/** Manually trigger report generation (admin) */
export async function generateReportsNow(
  targetDate?: string
): Promise<DailyReportResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<DailyReportResponse[]>>(
        '/jobs/reports/generate-now',
        null,
        { params: targetDate ? { target_date: targetDate } : undefined }
      );
      return data.data ?? [];
    },
    async () => {
      const { generateReportsNow: local } = await import('../local/services/job-service');
      return await local(targetDate) as unknown as DailyReportResponse[];
    },
  );
}


// =================================================================
// JOB PREFERENCES (Phase 7A — Smart Suggestions)
// =================================================================

/** Get all learned preferences for a job (brands, colors, suppliers, parts) */
export async function getJobPreferences(
  jobId: number,
  params?: { preference_type?: string; category?: string }
): Promise<JobPreferenceResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobPreferenceResponse[]>>(
        `/jobs/${jobId}/preferences`,
        { params }
      );
      return data.data ?? [];
    },
    async () => {
      const { getJobPreferences: local } = await import('../local/services/job-service');
      return await local(jobId, params) as unknown as JobPreferenceResponse[];
    },
  );
}

/**
 * Get ranked smart suggestions for the unified order form.
 *
 * Returns a summary grouped by type (brands, colors, suppliers, parts)
 * that the form uses to auto-filter the part catalog.
 */
export async function getJobSuggestions(
  jobId: number,
  category?: string
): Promise<JobPreferencesSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobPreferencesSummary>>(
        `/jobs/${jobId}/suggestions`,
        { params: category ? { category } : undefined }
      );
      return data.data!;
    },
    async () => {
      const { getJobSuggestions: local } = await import('../local/services/job-service');
      return await local(jobId, category) as unknown as JobPreferencesSummary;
    },
  );
}

/** Toggle a learned preference on or off */
export async function toggleJobPreference(
  jobId: number,
  prefId: number,
  toggle: JobPreferenceToggle
): Promise<JobPreferenceResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<JobPreferenceResponse>>(
        `/jobs/${jobId}/preferences/${prefId}`,
        toggle
      );
      return data.data!;
    },
    async () => {
      const { toggleJobPreference: local } = await import('../local/services/job-service');
      return await local(jobId, prefId, toggle) as unknown as JobPreferenceResponse;
    },
  );
}


// =================================================================
// EXPLICIT PREFERRED SUPPLIERS
// =================================================================

/** Get manually set preferred suppliers for a job (primary first, then backups). */
export async function getJobPreferredSuppliers(
  jobId: number
): Promise<ExplicitSupplierResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ExplicitSupplierResponse[]>>(
        `/jobs/${jobId}/preferred-suppliers`
      );
      return data.data ?? [];
    },
    async () => {
      const { getJobPreferredSuppliers: local } = await import('../local/services/job-service');
      return await local(jobId) as unknown as ExplicitSupplierResponse[];
    },
  );
}

/** Set explicit preferred suppliers for a job. First = primary, rest = backups. */
export async function setJobPreferredSuppliers(
  jobId: number,
  suppliers: JobPreferredSuppliersUpdate
): Promise<{ id: number; supplier_id: number; rank: number }[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number; supplier_id: number; rank: number }[]>>(
        `/jobs/${jobId}/preferred-suppliers`,
        suppliers
      );
      return data.data!;
    },
    async () => {
      const { setJobPreferredSuppliers: local } = await import('../local/services/job-service');
      const ids = (suppliers as any).suppliers?.map((s: any) => s.supplier_id) ?? [];
      return await local(jobId, ids);
    },
  );
}


// =================================================================
// JOB TEAM MEMBERS
// =================================================================

/** List all employees assigned to a job's team */
export async function getJobTeam(jobId: number): Promise<JobTeamMember[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobTeamMember[]>>(
        `/jobs/${jobId}/team`
      );
      return data.data ?? [];
    },
    async () => {
      const { getJobTeam: local } = await import('../local/services/job-service');
      return await local(jobId) as unknown as JobTeamMember[];
    },
  );
}

/** Add an employee to a job's team */
export async function addJobTeamMember(
  jobId: number,
  payload: { user_id: number; role?: 'lead' | 'member'; notes?: string }
): Promise<JobTeamMember> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<JobTeamMember>>(
        `/jobs/${jobId}/team`,
        payload
      );
      return data.data!;
    },
    async () => {
      const { addJobTeamMember: local } = await import('../local/services/job-service');
      return await local(jobId, payload, 0) as unknown as JobTeamMember;
    },
  );
}

/** Remove a team member from a job */
export async function removeJobTeamMember(
  jobId: number,
  memberId: number
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/jobs/${jobId}/team/${memberId}`);
    },
    async () => {
      const { removeJobTeamMember: local } = await import('../local/services/job-service');
      await local(jobId, memberId);
    },
  );
}
