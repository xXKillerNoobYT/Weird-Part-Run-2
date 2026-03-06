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
