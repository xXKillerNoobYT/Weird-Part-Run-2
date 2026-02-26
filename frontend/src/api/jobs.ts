/**
 * Jobs API functions — job CRUD, labor clock in/out, questions,
 * parts consumption, and daily reports.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';
import type {
  // Jobs
  JobCreate,
  JobUpdate,
  JobResponse,
  JobListItem,
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
} from '../lib/types';


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
  const { data } = await apiClient.get<ApiResponse<JobListItem[]>>(
    '/jobs/active',
    { params }
  );
  return data.data ?? [];
}

/** Create a new job */
export async function createJob(job: JobCreate): Promise<JobResponse> {
  const { data } = await apiClient.post<ApiResponse<JobResponse>>(
    '/jobs',
    job
  );
  return data.data!;
}

/** Get full job detail */
export async function getJob(jobId: number): Promise<JobResponse> {
  const { data } = await apiClient.get<ApiResponse<JobResponse>>(
    `/jobs/${jobId}`
  );
  return data.data!;
}

/** Update job information */
export async function updateJob(
  jobId: number,
  updates: JobUpdate
): Promise<JobResponse> {
  const { data } = await apiClient.put<ApiResponse<JobResponse>>(
    `/jobs/${jobId}`,
    updates
  );
  return data.data!;
}

/** Change job status */
export async function updateJobStatus(
  jobId: number,
  status: string
): Promise<JobResponse> {
  const { data } = await apiClient.patch<ApiResponse<JobResponse>>(
    `/jobs/${jobId}/status`,
    { status }
  );
  return data.data!;
}


// =================================================================
// LABOR / CLOCK IN-OUT
// =================================================================

/** Clock in to a job */
export async function clockIn(
  jobId: number,
  request: ClockInRequest
): Promise<LaborEntryResponse> {
  const { data } = await apiClient.post<ApiResponse<LaborEntryResponse>>(
    `/jobs/${jobId}/clock-in`,
    request
  );
  return data.data!;
}

/** Clock out from current job */
export async function clockOut(
  request: ClockOutRequest
): Promise<LaborEntryResponse> {
  const { data } = await apiClient.post<ApiResponse<LaborEntryResponse>>(
    '/jobs/clock-out',
    request
  );
  return data.data!;
}

/** Get current user's active clock entry */
export async function getMyClock(): Promise<ActiveClockResponse> {
  const { data } = await apiClient.get<ApiResponse<ActiveClockResponse>>(
    '/jobs/my-clock'
  );
  return data.data!;
}

/** Get labor entries for a specific job */
export async function getJobLabor(
  jobId: number,
  params?: { date_from?: string; date_to?: string }
): Promise<LaborEntryResponse[]> {
  const { data } = await apiClient.get<ApiResponse<LaborEntryResponse[]>>(
    `/jobs/${jobId}/labor`,
    { params }
  );
  return data.data ?? [];
}

/** Get current user's labor history */
export async function getMyLabor(
  params?: { date_from?: string; date_to?: string }
): Promise<LaborEntryResponse[]> {
  const { data } = await apiClient.get<ApiResponse<LaborEntryResponse[]>>(
    '/jobs/my-labor',
    { params }
  );
  return data.data ?? [];
}


// =================================================================
// PARTS CONSUMPTION
// =================================================================

/** List parts consumed on a job */
export async function getJobParts(jobId: number): Promise<JobPartResponse[]> {
  const { data } = await apiClient.get<ApiResponse<JobPartResponse[]>>(
    `/jobs/${jobId}/parts`
  );
  return data.data ?? [];
}

/** Record part consumption on a job */
export async function consumePart(
  jobId: number,
  request: JobPartConsumeRequest
): Promise<JobPartResponse> {
  const { data } = await apiClient.post<ApiResponse<JobPartResponse>>(
    `/jobs/${jobId}/parts/consume`,
    request
  );
  return data.data!;
}


// =================================================================
// GLOBAL CLOCK-OUT QUESTIONS
// =================================================================

/** List global clock-out questions */
export async function getGlobalQuestions(
  activeOnly: boolean = true
): Promise<ClockOutQuestionResponse[]> {
  const { data } = await apiClient.get<ApiResponse<ClockOutQuestionResponse[]>>(
    '/jobs/questions/global',
    { params: { active_only: activeOnly } }
  );
  return data.data ?? [];
}

/** Create a new global question */
export async function createGlobalQuestion(
  question: ClockOutQuestionCreate
): Promise<ClockOutQuestionResponse> {
  const { data } = await apiClient.post<ApiResponse<ClockOutQuestionResponse>>(
    '/jobs/questions/global',
    question
  );
  return data.data!;
}

/** Update a global question */
export async function updateGlobalQuestion(
  questionId: number,
  question: ClockOutQuestionCreate
): Promise<ClockOutQuestionResponse> {
  const { data } = await apiClient.put<ApiResponse<ClockOutQuestionResponse>>(
    `/jobs/questions/global/${questionId}`,
    question
  );
  return data.data!;
}

/** Reorder global questions */
export async function reorderGlobalQuestions(
  orderedIds: number[]
): Promise<void> {
  await apiClient.put<ApiResponse<StatusMessage>>(
    '/jobs/questions/global/reorder',
    { ordered_ids: orderedIds }
  );
}

/** Deactivate (soft-delete) a global question */
export async function deactivateGlobalQuestion(
  questionId: number
): Promise<void> {
  await apiClient.delete<ApiResponse<StatusMessage>>(
    `/jobs/questions/global/${questionId}`
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
  const { data } = await apiClient.get<ApiResponse<OneTimeQuestionResponse[]>>(
    `/jobs/${jobId}/questions/one-time`,
    { params: { pending_only: pendingOnly } }
  );
  return data.data ?? [];
}

/** Create a one-time question for a job */
export async function createOneTimeQuestion(
  jobId: number,
  question: OneTimeQuestionCreate
): Promise<OneTimeQuestionResponse> {
  const { data } = await apiClient.post<ApiResponse<OneTimeQuestionResponse>>(
    `/jobs/${jobId}/questions/one-time`,
    question
  );
  return data.data!;
}

/** Answer a one-time question */
export async function answerOneTimeQuestion(
  questionId: number,
  answerText: string | null
): Promise<OneTimeQuestionResponse> {
  const { data } = await apiClient.post<ApiResponse<OneTimeQuestionResponse>>(
    `/jobs/questions/one-time/${questionId}/answer`,
    { answer_text: answerText }
  );
  return data.data!;
}


// =================================================================
// CLOCK-OUT BUNDLE
// =================================================================

/** Get all questions for the clock-out flow */
export async function getClockOutBundle(
  jobId: number
): Promise<ClockOutBundle> {
  const { data } = await apiClient.get<ApiResponse<ClockOutBundle>>(
    `/jobs/${jobId}/clock-out-bundle`
  );
  return data.data!;
}


// =================================================================
// DAILY REPORTS
// =================================================================

/** List all daily reports across jobs */
export async function getAllReports(
  params?: { date_from?: string; date_to?: string }
): Promise<DailyReportResponse[]> {
  const { data } = await apiClient.get<ApiResponse<DailyReportResponse[]>>(
    '/jobs/reports/all',
    { params }
  );
  return data.data ?? [];
}

/** List daily reports for a specific job */
export async function getJobReports(
  jobId: number
): Promise<DailyReportResponse[]> {
  const { data } = await apiClient.get<ApiResponse<DailyReportResponse[]>>(
    `/jobs/${jobId}/reports`
  );
  return data.data ?? [];
}

/** Get full daily report for a specific job and date */
export async function getReport(
  jobId: number,
  reportDate: string
): Promise<DailyReportFull> {
  const { data } = await apiClient.get<ApiResponse<DailyReportFull>>(
    `/jobs/${jobId}/reports/${reportDate}`
  );
  return data.data!;
}

/** Manually trigger report generation (admin) */
export async function generateReportsNow(
  targetDate?: string
): Promise<DailyReportResponse[]> {
  const { data } = await apiClient.post<ApiResponse<DailyReportResponse[]>>(
    '/jobs/reports/generate-now',
    null,
    { params: targetDate ? { target_date: targetDate } : undefined }
  );
  return data.data ?? [];
}
