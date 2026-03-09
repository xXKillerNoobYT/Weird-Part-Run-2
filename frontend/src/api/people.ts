/**
 * People API functions — employees, certifications, wages, notes, skills,
 * hats/roles, and permission matrix.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import type {
  ApiResponse,
  PaginatedData,
  // Employees
  EmployeeListItem,
  EmployeeDetail,
  EmployeeCreate,
  EmployeeUpdate,
  // Certifications
  CertificationResponse,
  CertificationCreate,
  CertificationUpdate,
  ExpiringCertification,
  // Wages
  WageHistoryResponse,
  WageHistoryCreate,
  // Notes
  EmployeeNoteResponse,
  EmployeeNoteCreate,
  EmployeeNoteUpdate,
  // Skills
  UserSkillResponse,
  UserSkillCreate,
  UserSkillUpdate,
  // Hats
  HatDetailResponse,
  HatCreate,
  HatUpdate,
  // Permissions
  PermissionMatrixData,
  // Elevations
  JobLeadElevationResponse,
  JobLeadElevationCreate,
  // Teams
  EmployeeTeamListItem,
  EmployeeTeamDetail,
  EmployeeTeamCreate,
  EmployeeTeamUpdate,
  TeamMemberAdd,
} from '../lib/types';


// =================================================================
// EMPLOYEES
// =================================================================

export interface EmployeeListParams {
  search?: string;
  is_active?: boolean;
  hat_id?: number;
  page?: number;
  page_size?: number;
}

/** Paginated employee list with search/filters */
export async function getEmployees(
  params: EmployeeListParams = {}
): Promise<PaginatedData<EmployeeListItem>> {
  const { data } = await apiClient.get<ApiResponse<PaginatedData<EmployeeListItem>>>(
    '/people/employees',
    { params },
  );
  return data.data!;
}

/** Full employee detail with all related data */
export async function getEmployee(userId: number): Promise<EmployeeDetail> {
  const { data } = await apiClient.get<ApiResponse<EmployeeDetail>>(
    `/people/employees/${userId}`,
  );
  return data.data!;
}

/** Create a new employee */
export async function createEmployee(employee: EmployeeCreate): Promise<EmployeeDetail> {
  const { data } = await apiClient.post<ApiResponse<EmployeeDetail>>(
    '/people/employees',
    employee,
  );
  return data.data!;
}

/** Update employee fields */
export async function updateEmployee(
  userId: number,
  updates: EmployeeUpdate,
): Promise<EmployeeDetail> {
  const { data } = await apiClient.put<ApiResponse<EmployeeDetail>>(
    `/people/employees/${userId}`,
    updates,
  );
  return data.data!;
}

/** Activate or deactivate an employee */
export async function toggleEmployeeActive(
  userId: number,
  isActive: boolean,
): Promise<{ user_id: number; is_active: boolean }> {
  const { data } = await apiClient.patch<ApiResponse<{ user_id: number; is_active: boolean }>>(
    `/people/employees/${userId}/toggle-active`,
    null,
    { params: { is_active: isActive } },
  );
  return data.data!;
}


// =================================================================
// CERTIFICATIONS
// =================================================================

/** Get all certifications for an employee */
export async function getCertifications(userId: number): Promise<CertificationResponse[]> {
  const { data } = await apiClient.get<ApiResponse<CertificationResponse[]>>(
    `/people/employees/${userId}/certifications`,
  );
  return data.data ?? [];
}

/** Add a certification to an employee */
export async function createCertification(
  userId: number,
  cert: CertificationCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/people/employees/${userId}/certifications`,
    cert,
  );
  return data.data!;
}

/** Update an existing certification */
export async function updateCertification(
  certId: number,
  updates: CertificationUpdate,
): Promise<{ id: number }> {
  const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
    `/people/certifications/${certId}`,
    updates,
  );
  return data.data!;
}

/** Delete a certification */
export async function deleteCertification(certId: number): Promise<void> {
  await apiClient.delete(`/people/certifications/${certId}`);
}

/** Get certifications expiring within N days (all employees) */
export async function getExpiringCertifications(
  days: number = 30,
): Promise<ExpiringCertification[]> {
  const { data } = await apiClient.get<ApiResponse<ExpiringCertification[]>>(
    '/people/certifications/expiring',
    { params: { days } },
  );
  return data.data ?? [];
}


// =================================================================
// WAGE HISTORY
// =================================================================

/** Get full wage history for an employee */
export async function getWageHistory(userId: number): Promise<WageHistoryResponse[]> {
  const { data } = await apiClient.get<ApiResponse<WageHistoryResponse[]>>(
    `/people/employees/${userId}/wages`,
  );
  return data.data ?? [];
}

/** Add a wage entry (also updates employee's current pay_rate) */
export async function createWageEntry(
  userId: number,
  entry: WageHistoryCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/people/employees/${userId}/wages`,
    entry,
  );
  return data.data!;
}


// =================================================================
// EMPLOYEE NOTES
// =================================================================

/** Get notes for an employee */
export async function getEmployeeNotes(
  userId: number,
  noteType?: string,
): Promise<EmployeeNoteResponse[]> {
  const { data } = await apiClient.get<ApiResponse<EmployeeNoteResponse[]>>(
    `/people/employees/${userId}/notes`,
    { params: noteType ? { note_type: noteType } : {} },
  );
  return data.data ?? [];
}

/** Add a note to an employee's record */
export async function createEmployeeNote(
  userId: number,
  note: EmployeeNoteCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/people/employees/${userId}/notes`,
    note,
  );
  return data.data!;
}

/** Update a note */
export async function updateEmployeeNote(
  noteId: number,
  updates: EmployeeNoteUpdate,
): Promise<{ id: number }> {
  const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
    `/people/notes/${noteId}`,
    updates,
  );
  return data.data!;
}

/** Delete a note */
export async function deleteEmployeeNote(noteId: number): Promise<void> {
  await apiClient.delete(`/people/notes/${noteId}`);
}


// =================================================================
// SKILLS
// =================================================================

/** Get all skills for an employee */
export async function getSkills(userId: number): Promise<UserSkillResponse[]> {
  const { data } = await apiClient.get<ApiResponse<UserSkillResponse[]>>(
    `/people/employees/${userId}/skills`,
  );
  return data.data ?? [];
}

/** Add a skill to an employee */
export async function createSkill(
  userId: number,
  skill: UserSkillCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/people/employees/${userId}/skills`,
    skill,
  );
  return data.data!;
}

/** Update a skill */
export async function updateSkill(
  skillId: number,
  updates: UserSkillUpdate,
): Promise<{ id: number }> {
  const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
    `/people/skills/${skillId}`,
    updates,
  );
  return data.data!;
}

/** Delete a skill */
export async function deleteSkill(skillId: number): Promise<void> {
  await apiClient.delete(`/people/skills/${skillId}`);
}


// =================================================================
// HATS (ROLES)
// =================================================================

/** Get all hats with permissions and user counts */
export async function getHats(): Promise<HatDetailResponse[]> {
  const { data } = await apiClient.get<ApiResponse<HatDetailResponse[]>>(
    '/people/hats',
  );
  return data.data ?? [];
}

/** Create a new hat */
export async function createHat(hat: HatCreate): Promise<HatDetailResponse> {
  const { data } = await apiClient.post<ApiResponse<HatDetailResponse>>(
    '/people/hats',
    hat,
  );
  return data.data!;
}

/** Update a hat */
export async function updateHat(
  hatId: number,
  updates: HatUpdate,
): Promise<HatDetailResponse> {
  const { data } = await apiClient.put<ApiResponse<HatDetailResponse>>(
    `/people/hats/${hatId}`,
    updates,
  );
  return data.data!;
}

/** Delete a hat (built-in hats cannot be deleted) */
export async function deleteHat(hatId: number): Promise<void> {
  await apiClient.delete(`/people/hats/${hatId}`);
}

/** Replace all permissions for a hat */
export async function setHatPermissions(
  hatId: number,
  permissionKeys: string[],
): Promise<HatDetailResponse> {
  const { data } = await apiClient.put<ApiResponse<HatDetailResponse>>(
    `/people/hats/${hatId}/permissions`,
    { permission_keys: permissionKeys },
  );
  return data.data!;
}


// =================================================================
// PERMISSION MATRIX
// =================================================================

/** Full permission matrix: all hats × all permissions, grouped by domain */
export async function getPermissionMatrix(): Promise<PermissionMatrixData> {
  const { data } = await apiClient.get<ApiResponse<PermissionMatrixData>>(
    '/people/permissions/matrix',
  );
  return data.data!;
}

/** Get all known permission keys */
export async function getPermissionKeys(): Promise<string[]> {
  const { data } = await apiClient.get<ApiResponse<string[]>>(
    '/people/permissions/keys',
  );
  return data.data ?? [];
}


// =================================================================
// JOB LEAD ELEVATIONS
// =================================================================

/** Get all job-lead elevations for an employee */
export async function getUserElevations(
  userId: number,
): Promise<JobLeadElevationResponse[]> {
  const { data } = await apiClient.get<ApiResponse<JobLeadElevationResponse[]>>(
    `/people/employees/${userId}/elevations`,
  );
  return data.data!;
}

/** Grant a job-specific permission elevation to an employee */
export async function grantElevation(
  userId: number,
  elevation: JobLeadElevationCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/people/employees/${userId}/elevations`,
    elevation,
  );
  return data.data!;
}

/** Revoke a single job-lead elevation */
export async function revokeElevation(
  elevationId: number,
): Promise<{ id: number }> {
  const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
    `/people/elevations/${elevationId}`,
  );
  return data.data!;
}

/** Revoke all elevations for an employee on a specific job */
export async function revokeAllElevationsForJob(
  userId: number,
  jobId: number,
): Promise<{ count: number }> {
  const { data } = await apiClient.delete<ApiResponse<{ count: number }>>(
    `/people/employees/${userId}/elevations/job/${jobId}`,
  );
  return data.data!;
}


// =================================================================
// EMPLOYEE AVATAR
// =================================================================

/** Upload or replace an employee's avatar photo */
export async function uploadEmployeeAvatar(
  employeeId: number,
  file: File,
): Promise<{ avatar_url: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<{ avatar_url: string }>>(
    `/people/employees/${employeeId}/avatar`,
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}


// =================================================================
// CERTIFICATION DOCUMENTS
// =================================================================

/** Upload a certification document (scan, PDF, photo) */
export async function uploadCertificationDocument(
  certId: number,
  file: File,
): Promise<{ document_path: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<{ document_path: string }>>(
    `/people/certifications/${certId}/document`,
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}


// =================================================================
// CSV IMPORT
// =================================================================

export interface CSVImportResult {
  created: number;
  skipped: number;
  errors: { row: number; error: string }[];
}

/** Import employees from a CSV file */
export async function importEmployeesCSV(file: File): Promise<CSVImportResult> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<CSVImportResult>>(
    '/people/employees/import',
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}


// =================================================================
// EMPLOYEE TEAMS
// =================================================================

/** List all teams with member counts */
export async function getTeams(
  activeOnly = true,
): Promise<EmployeeTeamListItem[]> {
  const { data } = await apiClient.get<ApiResponse<EmployeeTeamListItem[]>>(
    '/people/teams',
    { params: { active_only: activeOnly } },
  );
  return data.data!;
}

/** Get a single team with full member list */
export async function getTeam(teamId: number): Promise<EmployeeTeamDetail> {
  const { data } = await apiClient.get<ApiResponse<EmployeeTeamDetail>>(
    `/people/teams/${teamId}`,
  );
  return data.data!;
}

/** Create a new team */
export async function createTeam(
  team: EmployeeTeamCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    '/people/teams',
    team,
  );
  return data.data!;
}

/** Update a team */
export async function updateTeam(
  teamId: number,
  updates: EmployeeTeamUpdate,
): Promise<{ id: number }> {
  const { data } = await apiClient.patch<ApiResponse<{ id: number }>>(
    `/people/teams/${teamId}`,
    updates,
  );
  return data.data!;
}

/** Delete a team */
export async function deleteTeam(teamId: number): Promise<{ id: number }> {
  const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
    `/people/teams/${teamId}`,
  );
  return data.data!;
}

/** Add a member to a team */
export async function addTeamMember(
  teamId: number,
  member: TeamMemberAdd,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    `/people/teams/${teamId}/members`,
    member,
  );
  return data.data!;
}

/** Remove a member from a team */
export async function removeTeamMember(
  teamId: number,
  userId: number,
): Promise<void> {
  await apiClient.delete(`/people/teams/${teamId}/members/${userId}`);
}

/** Update a team member's role */
export async function updateTeamMemberRole(
  teamId: number,
  userId: number,
  role: 'lead' | 'member',
): Promise<void> {
  await apiClient.patch(`/people/teams/${teamId}/members/${userId}`, { role });
}

/** Get all teams an employee belongs to */
export async function getEmployeeTeams(
  userId: number,
): Promise<{ id: number; name: string; role: string }[]> {
  const { data } = await apiClient.get<ApiResponse<{ id: number; name: string; role: string }[]>>(
    `/people/employees/${userId}/teams`,
  );
  return data.data!;
}
