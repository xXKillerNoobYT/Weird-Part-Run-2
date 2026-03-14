/**
 * People services — barrel re-export.
 *
 * Split from the original monolithic people-service.ts into domain files:
 *   - certifications-service.ts  (cert CRUD + expiry + document upload)
 *   - wages-service.ts           (immutable wage history)
 *   - notes-service.ts           (employee notes CRUD)
 *   - skills-service.ts          (user skills + expert search)
 *   - teams-service.ts           (teams + team members)
 *   - employees-service.ts       (user CRUD, detail, CSV import, avatar)
 *   - hats-service.ts            (roles, permissions, permission matrix)
 *   - elevations-service.ts      (job-lead permission elevations)
 */

export {
  // Types
  type CertificationCreate,
  type CertificationUpdate,
  type Certification,
  // Functions
  createCertification,
  getCertification,
  getUserCertifications,
  getExpiringCertifications,
  updateCertification,
  deleteCertification,
  uploadCertificationDocument,
} from './certifications-service';

export {
  // Types
  type WageHistoryCreate,
  type WageHistoryEntry,
  // Functions
  addWageEntry,
  getWageHistory,
  getCurrentPayRate,
} from './wages-service';

export {
  // Types
  type EmployeeNoteCreate,
  type EmployeeNoteUpdate,
  type EmployeeNote,
  // Functions
  createEmployeeNote,
  getEmployeeNotes,
  updateEmployeeNote,
  deleteEmployeeNote,
} from './notes-service';

export {
  // Types
  type UserSkillCreate,
  type UserSkillUpdate,
  type UserSkill,
  // Functions
  addUserSkill,
  getUserSkills,
  updateUserSkill,
  deleteUserSkill,
  searchSkills,
} from './skills-service';

export {
  // Types
  type TeamCreate,
  type TeamUpdate,
  type Team,
  type TeamMember,
  // Functions
  createTeam,
  getTeam,
  listTeams,
  updateTeam,
  deleteTeam,
  addTeamMember,
  getTeamMembers,
  removeTeamMember,
  getUserTeams,
  updateTeamMemberRole,
} from './teams-service';

export {
  // Types
  type EmployeeListParams,
  type EmployeeListItem,
  type EmployeeDetail,
  type EmployeeCreateData,
  type EmployeeUpdateData,
  type PaginatedResult,
  type CSVImportResult,
  // Functions
  getEmployees,
  getEmployee,
  createEmployee,
  updateEmployee,
  toggleEmployeeActive,
  uploadEmployeeAvatar,
  importEmployeesCSV,
} from './employees-service';

export {
  // Types
  type HatDetail,
  type HatCreateData,
  type HatUpdateData,
  type PermissionMatrixRow,
  type PermissionMatrixData,
  // Functions
  getHats,
  getHat,
  createHat,
  updateHat,
  deleteHat,
  setHatPermissions,
  getPermissionMatrix,
  getPermissionKeys,
} from './hats-service';

export {
  // Types
  type JobLeadElevation,
  type JobLeadElevationCreateData,
  // Functions
  getUserElevations,
  grantElevation,
  revokeElevation,
  revokeAllElevationsForJob,
} from './elevations-service';
