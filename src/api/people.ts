/**
 * People API functions — employees, certifications, wages, notes, skills,
 * hats/roles, and permission matrix.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PaginatedData<EmployeeListItem>>>(
        '/people/employees',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getEmployees } = await import('../local/services/people-service');
      return getEmployees(params) as unknown as PaginatedData<EmployeeListItem>;
    },
  );
}

/** Full employee detail with all related data */
export async function getEmployee(userId: number): Promise<EmployeeDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EmployeeDetail>>(
        `/people/employees/${userId}`,
      );
      return data.data!;
    },
    async () => {
      const { getEmployee } = await import('../local/services/people-service');
      return getEmployee(userId) as unknown as EmployeeDetail;
    },
  );
}

/** Create a new employee */
export async function createEmployee(employee: EmployeeCreate): Promise<EmployeeDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<EmployeeDetail>>(
        '/people/employees',
        employee,
      );
      return data.data!;
    },
    async () => {
      const { createEmployee } = await import('../local/services/people-service');
      return createEmployee(employee) as unknown as EmployeeDetail;
    },
  );
}

/** Update employee fields */
export async function updateEmployee(
  userId: number,
  updates: EmployeeUpdate,
): Promise<EmployeeDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<EmployeeDetail>>(
        `/people/employees/${userId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateEmployee } = await import('../local/services/people-service');
      return updateEmployee(userId, updates) as unknown as EmployeeDetail;
    },
  );
}

/** Activate or deactivate an employee */
export async function toggleEmployeeActive(
  userId: number,
  isActive: boolean,
): Promise<{ user_id: number; is_active: boolean }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<{ user_id: number; is_active: boolean }>>(
        `/people/employees/${userId}/toggle-active`,
        null,
        { params: { is_active: isActive } },
      );
      return data.data!;
    },
    async () => {
      const { toggleEmployeeActive } = await import('../local/services/people-service');
      return toggleEmployeeActive(userId, isActive) as unknown as { user_id: number; is_active: boolean };
    },
  );
}


// =================================================================
// CERTIFICATIONS
// =================================================================

/** Get all certifications for an employee */
export async function getCertifications(userId: number): Promise<CertificationResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CertificationResponse[]>>(
        `/people/employees/${userId}/certifications`,
      );
      return data.data ?? [];
    },
    async () => {
      const { getUserCertifications } = await import('../local/services/people-service');
      return getUserCertifications(userId) as unknown as CertificationResponse[];
    },
  );
}

/** Add a certification to an employee */
export async function createCertification(
  userId: number,
  cert: CertificationCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/people/employees/${userId}/certifications`,
        cert,
      );
      return data.data!;
    },
    async () => {
      const { createCertification: local } = await import('../local/services/people-service');
      return local({ user_id: userId, ...cert } as any) as unknown as { id: number };
    },
  );
}

/** Update an existing certification */
export async function updateCertification(
  certId: number,
  updates: CertificationUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/people/certifications/${certId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateCertification: local } = await import('../local/services/people-service');
      return local(certId, updates as never) as unknown as { id: number };
    },
  );
}

/** Delete a certification */
export async function deleteCertification(certId: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/people/certifications/${certId}`);
    },
    async () => {
      const { deleteCertification } = await import('../local/services/people-service');
      await deleteCertification(certId);
    },
  );
}

/** Get certifications expiring within N days (all employees) */
export async function getExpiringCertifications(
  days: number = 30,
): Promise<ExpiringCertification[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ExpiringCertification[]>>(
        '/people/certifications/expiring',
        { params: { days } },
      );
      return data.data ?? [];
    },
    async () => {
      const { getExpiringCertifications } = await import('../local/services/people-service');
      return getExpiringCertifications(days) as unknown as ExpiringCertification[];
    },
  );
}


// =================================================================
// WAGE HISTORY
// =================================================================

/** Get full wage history for an employee */
export async function getWageHistory(userId: number): Promise<WageHistoryResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<WageHistoryResponse[]>>(
        `/people/employees/${userId}/wages`,
      );
      return data.data ?? [];
    },
    async () => {
      const { getWageHistory } = await import('../local/services/people-service');
      return getWageHistory(userId) as unknown as WageHistoryResponse[];
    },
  );
}

/** Add a wage entry (also updates employee's current pay_rate) */
export async function createWageEntry(
  userId: number,
  entry: WageHistoryCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/people/employees/${userId}/wages`,
        entry,
      );
      return data.data!;
    },
    async () => {
      const { addWageEntry } = await import('../local/services/people-service');
      return addWageEntry({ user_id: userId, ...entry } as any) as unknown as { id: number };
    },
  );
}


// =================================================================
// EMPLOYEE NOTES
// =================================================================

/** Get notes for an employee */
export async function getEmployeeNotes(
  userId: number,
  noteType?: string,
): Promise<EmployeeNoteResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EmployeeNoteResponse[]>>(
        `/people/employees/${userId}/notes`,
        { params: noteType ? { note_type: noteType } : {} },
      );
      return data.data ?? [];
    },
    async () => {
      const { getEmployeeNotes: local } = await import('../local/services/people-service');
      return local(userId, noteType ? { note_type: noteType } : undefined) as unknown as EmployeeNoteResponse[];
    },
  );
}

/** Add a note to an employee's record */
export async function createEmployeeNote(
  userId: number,
  note: EmployeeNoteCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/people/employees/${userId}/notes`,
        note,
      );
      return data.data!;
    },
    async () => {
      const { createEmployeeNote: local } = await import('../local/services/people-service');
      return local({ user_id: userId, ...note } as never) as unknown as { id: number };
    },
  );
}

/** Update a note */
export async function updateEmployeeNote(
  noteId: number,
  updates: EmployeeNoteUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/people/notes/${noteId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateEmployeeNote: local } = await import('../local/services/people-service');
      return local(noteId, updates as never) as unknown as { id: number };
    },
  );
}

/** Delete a note */
export async function deleteEmployeeNote(noteId: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/people/notes/${noteId}`);
    },
    async () => {
      const { deleteEmployeeNote } = await import('../local/services/people-service');
      await deleteEmployeeNote(noteId);
    },
  );
}


// =================================================================
// SKILLS
// =================================================================

/** Get all skills for an employee */
export async function getSkills(userId: number): Promise<UserSkillResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<UserSkillResponse[]>>(
        `/people/employees/${userId}/skills`,
      );
      return data.data ?? [];
    },
    async () => {
      const { getUserSkills } = await import('../local/services/people-service');
      return getUserSkills(userId) as unknown as UserSkillResponse[];
    },
  );
}

/** Add a skill to an employee */
export async function createSkill(
  userId: number,
  skill: UserSkillCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/people/employees/${userId}/skills`,
        skill,
      );
      return data.data!;
    },
    async () => {
      const { addUserSkill } = await import('../local/services/people-service');
      return addUserSkill({ user_id: userId, ...skill } as any) as unknown as { id: number };
    },
  );
}

/** Update a skill */
export async function updateSkill(
  skillId: number,
  updates: UserSkillUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<{ id: number }>>(
        `/people/skills/${skillId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateUserSkill } = await import('../local/services/people-service');
      return updateUserSkill(skillId, updates as any) as unknown as { id: number };
    },
  );
}

/** Delete a skill */
export async function deleteSkill(skillId: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/people/skills/${skillId}`);
    },
    async () => {
      const { deleteUserSkill } = await import('../local/services/people-service');
      await deleteUserSkill(skillId);
    },
  );
}


// =================================================================
// HATS (ROLES)
// =================================================================

/** Get all hats with permissions and user counts */
export async function getHats(): Promise<HatDetailResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<HatDetailResponse[]>>(
        '/people/hats',
      );
      return data.data ?? [];
    },
    async () => {
      const { getHats } = await import('../local/services/people-service');
      return getHats() as unknown as HatDetailResponse[];
    },
  );
}

/** Create a new hat */
export async function createHat(hat: HatCreate): Promise<HatDetailResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<HatDetailResponse>>(
        '/people/hats',
        hat,
      );
      return data.data!;
    },
    async () => {
      const { createHat } = await import('../local/services/people-service');
      return createHat(hat) as unknown as HatDetailResponse;
    },
  );
}

/** Update a hat */
export async function updateHat(
  hatId: number,
  updates: HatUpdate,
): Promise<HatDetailResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<HatDetailResponse>>(
        `/people/hats/${hatId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateHat } = await import('../local/services/people-service');
      return updateHat(hatId, updates) as unknown as HatDetailResponse;
    },
  );
}

/** Delete a hat (built-in hats cannot be deleted) */
export async function deleteHat(hatId: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/people/hats/${hatId}`);
    },
    async () => {
      const { deleteHat } = await import('../local/services/people-service');
      await deleteHat(hatId);
    },
  );
}

/** Replace all permissions for a hat */
export async function setHatPermissions(
  hatId: number,
  permissionKeys: string[],
): Promise<HatDetailResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<HatDetailResponse>>(
        `/people/hats/${hatId}/permissions`,
        { permission_keys: permissionKeys },
      );
      return data.data!;
    },
    async () => {
      const { setHatPermissions } = await import('../local/services/people-service');
      return setHatPermissions(hatId, permissionKeys) as unknown as HatDetailResponse;
    },
  );
}


// =================================================================
// PERMISSION MATRIX
// =================================================================

/** Full permission matrix: all hats × all permissions, grouped by domain */
export async function getPermissionMatrix(): Promise<PermissionMatrixData> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PermissionMatrixData>>(
        '/people/permissions/matrix',
      );
      return data.data!;
    },
    async () => {
      const { getPermissionMatrix } = await import('../local/services/people-service');
      return getPermissionMatrix() as unknown as PermissionMatrixData;
    },
  );
}

/** Get all known permission keys */
export async function getPermissionKeys(): Promise<string[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<string[]>>(
        '/people/permissions/keys',
      );
      return data.data ?? [];
    },
    async () => {
      const { getPermissionKeys } = await import('../local/services/people-service');
      return getPermissionKeys() as unknown as string[];
    },
  );
}


// =================================================================
// JOB LEAD ELEVATIONS
// =================================================================

/** Get all job-lead elevations for an employee */
export async function getUserElevations(
  userId: number,
): Promise<JobLeadElevationResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobLeadElevationResponse[]>>(
        `/people/employees/${userId}/elevations`,
      );
      return data.data!;
    },
    async () => {
      const { getUserElevations } = await import('../local/services/people-service');
      return getUserElevations(userId) as unknown as JobLeadElevationResponse[];
    },
  );
}

/** Grant a job-specific permission elevation to an employee */
export async function grantElevation(
  userId: number,
  elevation: JobLeadElevationCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/people/employees/${userId}/elevations`,
        elevation,
      );
      return data.data!;
    },
    async () => {
      const { grantElevation: local } = await import('../local/services/people-service');
      return local(userId, elevation as never, (elevation as unknown as Record<string, unknown>).granted_by as number ?? 0) as unknown as { id: number };
    },
  );
}

/** Revoke a single job-lead elevation */
export async function revokeElevation(
  elevationId: number,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
        `/people/elevations/${elevationId}`,
      );
      return data.data!;
    },
    async () => {
      const { revokeElevation } = await import('../local/services/people-service');
      return revokeElevation(elevationId) as unknown as { id: number };
    },
  );
}

/** Revoke all elevations for an employee on a specific job */
export async function revokeAllElevationsForJob(
  userId: number,
  jobId: number,
): Promise<{ count: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<{ count: number }>>(
        `/people/employees/${userId}/elevations/job/${jobId}`,
      );
      return data.data!;
    },
    async () => {
      const { revokeAllElevationsForJob } = await import('../local/services/people-service');
      return revokeAllElevationsForJob(userId, jobId) as unknown as { count: number };
    },
  );
}


// =================================================================
// EMPLOYEE AVATAR
// =================================================================

/** Upload or replace an employee's avatar photo */
export async function uploadEmployeeAvatar(
  employeeId: number,
  file: File,
): Promise<{ avatar_url: string }> {
  return adaptedRequest(
    async () => {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await apiClient.post<ApiResponse<{ avatar_url: string }>>(
        `/people/employees/${employeeId}/avatar`,
        formData,
        { headers: { 'Content-Type': 'multipart/form-data' } },
      );
      return data.data!;
    },
    async () => {
      const { uploadEmployeeAvatar: local } = await import('../local/services/people-service');
      return local(employeeId, file.name) as unknown as { avatar_url: string };
    },
  );
}


// =================================================================
// CERTIFICATION DOCUMENTS
// =================================================================

/** Upload a certification document (scan, PDF, photo) */
export async function uploadCertificationDocument(
  certId: number,
  file: File,
): Promise<{ document_path: string }> {
  return adaptedRequest(
    async () => {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await apiClient.post<ApiResponse<{ document_path: string }>>(
        `/people/certifications/${certId}/document`,
        formData,
        { headers: { 'Content-Type': 'multipart/form-data' } },
      );
      return data.data!;
    },
    async () => {
      const { uploadCertificationDocument: local } = await import('../local/services/people-service');
      return local(certId, file.name) as unknown as { document_path: string };
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

/** Import employees from a CSV file */
export async function importEmployeesCSV(file: File): Promise<CSVImportResult> {
  return adaptedRequest(
    async () => {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await apiClient.post<ApiResponse<CSVImportResult>>(
        '/people/employees/import',
        formData,
        { headers: { 'Content-Type': 'multipart/form-data' } },
      );
      return data.data!;
    },
    async () => {
      const { importEmployeesCSV: local } = await import('../local/services/people-service');
      const text = await file.text();
      return local(text) as unknown as CSVImportResult;
    },
  );
}


// =================================================================
// EMPLOYEE TEAMS
// =================================================================

/** List all teams with member counts */
export async function getTeams(
  activeOnly = true,
): Promise<EmployeeTeamListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EmployeeTeamListItem[]>>(
        '/people/teams',
        { params: { active_only: activeOnly } },
      );
      return data.data!;
    },
    async () => {
      const { listTeams } = await import('../local/services/people-service');
      return listTeams({ include_inactive: !activeOnly }) as unknown as EmployeeTeamListItem[];
    },
  );
}

/** Get a single team with full member list */
export async function getTeam(teamId: number): Promise<EmployeeTeamDetail> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<EmployeeTeamDetail>>(
        `/people/teams/${teamId}`,
      );
      return data.data!;
    },
    async () => {
      const { getTeam } = await import('../local/services/people-service');
      return getTeam(teamId) as unknown as EmployeeTeamDetail;
    },
  );
}

/** Create a new team */
export async function createTeam(
  team: EmployeeTeamCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        '/people/teams',
        team,
      );
      return data.data!;
    },
    async () => {
      const { createTeam } = await import('../local/services/people-service');
      return createTeam(team as any) as unknown as { id: number };
    },
  );
}

/** Update a team */
export async function updateTeam(
  teamId: number,
  updates: EmployeeTeamUpdate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<{ id: number }>>(
        `/people/teams/${teamId}`,
        updates,
      );
      return data.data!;
    },
    async () => {
      const { updateTeam: local } = await import('../local/services/people-service');
      return local(teamId, updates as never) as unknown as { id: number };
    },
  );
}

/** Delete a team */
export async function deleteTeam(teamId: number): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
        `/people/teams/${teamId}`,
      );
      return data.data!;
    },
    async () => {
      const { deleteTeam: local } = await import('../local/services/people-service');
      await local(teamId);
      return { id: teamId };
    },
  );
}

/** Add a member to a team */
export async function addTeamMember(
  teamId: number,
  member: TeamMemberAdd,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        `/people/teams/${teamId}/members`,
        member,
      );
      return data.data!;
    },
    async () => {
      const { addTeamMember: local } = await import('../local/services/people-service');
      const result = await local(teamId, member.user_id, member.role ?? 'member');
      return { id: result.id } as { id: number };
    },
  );
}

/** Remove a member from a team */
export async function removeTeamMember(
  teamId: number,
  userId: number,
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/people/teams/${teamId}/members/${userId}`);
    },
    async () => {
      // Local removeTeamMember takes memberId, not (teamId, userId)
      const { removeTeamMember: local } = await import('../local/services/people-service');
      await local(userId);
    },
  );
}

/** Update a team member's role */
export async function updateTeamMemberRole(
  teamId: number,
  userId: number,
  role: 'lead' | 'member',
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.patch(`/people/teams/${teamId}/members/${userId}`, { role });
    },
    async () => {
      const { updateTeamMemberRole } = await import('../local/services/people-service');
      await updateTeamMemberRole(teamId, userId, role);
    },
  );
}

/** Get all teams an employee belongs to */
export async function getEmployeeTeams(
  userId: number,
): Promise<{ id: number; name: string; role: string }[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<{ id: number; name: string; role: string }[]>>(
        `/people/employees/${userId}/teams`,
      );
      return data.data!;
    },
    async () => {
      const { getUserTeams } = await import('../local/services/people-service');
      return getUserTeams(userId) as unknown as { id: number; name: string; role: string }[];
    },
  );
}
