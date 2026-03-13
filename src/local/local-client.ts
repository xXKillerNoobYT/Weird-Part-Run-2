/**
 * Local Client — implements the same API surface as the HTTP client
 * for Tauri (offline) mode.
 *
 * Each method maps to an api/*.ts function but routes to the local
 * TypeScript service instead of making an HTTP request. The frontend
 * components don't know the difference — they call the same api
 * functions, which are routed here via the adapter when in native mode.
 *
 * This file re-exports all local service functions organized by domain,
 * matching the structure of the HTTP API client modules.
 */

// ── Auth ───────────────────────────────────────────────────────────
export {
  authenticateByPin,
  getActiveUsers,
  getUser,
  getUserPermissions,
  hasPermission,
} from './services/auth-service';

// ── Jobs ───────────────────────────────────────────────────────────
export {
  createJob,
  getJob,
  getActiveJobs,
  updateJob,
  updateJobStatus,
  getMyJobs,
  getJobsWithActiveClock,
  // Bill rate types
  getBillRateTypes,
  createBillRateType,
  updateBillRateType,
  deleteBillRateType,
  // Parts consumption
  getJobParts,
  consumePart,
  // Clock-out questions
  getGlobalQuestions,
  createGlobalQuestion,
  updateGlobalQuestion,
  reorderGlobalQuestions,
  deactivateGlobalQuestion,
  // One-time questions
  getOneTimeQuestions,
  createOneTimeQuestion,
  answerOneTimeQuestion,
  // Clock-out bundle
  getClockOutBundle,
  // Daily reports
  getAllReports as getAllJobReports,
  getJobReports,
  getReport as getJobReport,
  generateReportsNow,
  // Preferences
  getJobPreferences,
  getJobSuggestions,
  toggleJobPreference,
  // Preferred suppliers
  getJobPreferredSuppliers,
  setJobPreferredSuppliers,
  // Team
  getJobTeam,
  addJobTeamMember,
  removeJobTeamMember,
} from './services/job-service';

// ── Labor ──────────────────────────────────────────────────────────
export {
  clockIn,
  clockOut,
  getActiveClock,
  getLaborEntry,
  getLaborForJob,
  getLaborForUser,
  getTodaySummary,
} from './services/labor-service';

// ── Movement ───────────────────────────────────────────────────────
export {
  validateMovement,
  calculatePreview,
  executeMovement,
  getRecentMovements,
  getStockAtLocation,
} from './services/movement-service';

// ── Orders ─────────────────────────────────────────────────────────
export {
  createJPO,
  submitJPO,
  getJPO,
  getJPOLines,
  listJPOs,
  getMyOrders,
} from './services/order-service';

// ── Notebooks ──────────────────────────────────────────────────────
export {
  listNotebooks,
  getNotebook,
  createNotebook,
  createSection,
  createEntry,
  updateEntry,
  deleteEntry,
  updateTaskStatus,
  getTasksForJob,
  getMyTasks,
  // Templates (read-only synced data)
  listTemplates as listNotebookTemplates,
  getTemplateFull as getNotebookTemplateFull,
  // Job notebook
  getJobNotebook,
  // Notebook ops
  updateNotebook,
  archiveNotebook,
  // Section ops
  updateSection as updateNotebookSection,
  deleteSection as deleteNotebookSection,
  reorderSections,
  // Entry extras
  updateFieldValue,
  assignTask,
  reorderEntries,
  bulkUpdateTasks,
  // Job tasks (cross-cutting)
  getJobTasks,
} from './services/notebook-service';

// ── Warehouse ─────────────────────────────────────────────────────
export {
  getDashboardKPIs,
  getRecentActivity,
  getInventoryGrid,
  getPartStockDetail,
  searchParts as searchWarehouseParts,
} from './services/warehouse-service';

// ── Tools ──────────────────────────────────────────────────────────
export {
  listTools,
  getTool,
  getToolByBarcode,
  checkoutTool,
  returnTool,
  getMyTools,
  getToolsAtLocation,
  getKitTemplate,
  startVerification,
  completeVerification,
  getToolHistory,
} from './services/tool-service';

// ── Parts ──────────────────────────────────────────────────────────
export {
  // Hierarchy
  getHierarchy,
  // Categories
  getCategories,
  createCategory as createPartCategory,
  updateCategory as updatePartCategory,
  deleteCategory as deletePartCategory,
  // Styles
  listStylesByCategory,
  createStyle,
  updateStyle,
  deleteStyle,
  // Types
  listTypesByStyle,
  getType,
  createType,
  updateType,
  deleteType,
  getPartTypes,
  // Type ↔ Color links
  listTypeColors,
  linkColorsToType,
  unlinkColorFromType,
  // Type ↔ Brand links
  listTypeBrands,
  linkBrandToType,
  unlinkBrandFromType,
  listPartsForTypeBrand,
  quickCreatePart,
  // Colors
  listColors,
  createColor,
  updateColor,
  deleteColor,
  // Catalog
  listParts,
  getPart,
  searchParts,
  createPart as createPartLocal,
  updatePart as updatePartLocal,
  deletePart as deletePartLocal,
  getCatalogStats,
  getCatalogGroups,
  // Pending part numbers
  getPendingPartNumbers,
  getPendingPartNumbersCount,
  // Pricing
  updatePartPricing,
  // Stock
  getPartStock,
  getPartStockSummary,
  // Part ↔ Supplier links
  getPartSuppliers,
  addPartSupplierLink,
  removePartSupplierLink,
  // Brands
  listBrands,
  getBrand,
  createBrand,
  updateBrand,
  deleteBrand,
  // Brand ↔ Supplier links
  getBrandSuppliers,
  getSupplierBrands,
  createBrandSupplierLink,
  deleteBrandSupplierLink,
  // Suppliers
  listSuppliers,
  createSupplier,
  updateSupplier,
  deleteSupplier,
  // Forecasting
  getForecasting,
  recalculateForecasts,
  // Import / Export
  exportPartsCsv,
  importPartsCsv,
  // Companion rules
  listCompanionRules,
  createCompanionRule,
  updateCompanionRule,
  deleteCompanionRule,
  // Companion suggestions
  generateCompanionSuggestions,
  listCompanionSuggestions,
  decideCompanionSuggestion,
  // Companion stats & co-occurrence
  getCompanionStats,
  getCoOccurrences,
  refreshCoOccurrence,
  // Alternatives
  listPartAlternatives,
  linkPartAlternative,
  updatePartAlternative,
  unlinkPartAlternative,
} from './services/parts-service';

// ── Fleet ──────────────────────────────────────────────────────────
export {
  getMyVehicle,
  getVehicle,
  listVehicles,
  getVehicleAssignments,
  getTruckInventory,
} from './services/fleet-service';

// ── Scheduling ────────────────────────────────────────────────────
export {
  getMyDispatch,
  getTodayDispatch,
  getMySchedule,
  getMyTimeOff,
  getDispatchForDate,
} from './services/scheduling-service';

// ── Chat ───────────────────────────────────────────────────────────
export {
  getInbox,
  getChannelMessages,
  getChannelMembers,
  getPinnedMessages,
  sendMessage,
  editMessage,
  deleteMessage,
  pinMessage,
  unpinMessage,
  markChannelRead,
  listQAThreads,
  askQuestion,
  answerQuestion,
  getOrCreateJobChannel,
} from './services/chat-service';

// ── People & Employees ─────────────────────────────────────────────
export {
  getEmployees,
  getEmployee,
  createEmployee,
  updateEmployee,
  toggleEmployeeActive,
  createCertification,
  getCertification,
  getUserCertifications,
  getExpiringCertifications,
  updateCertification,
  deleteCertification,
  addWageEntry,
  getWageHistory,
  getCurrentPayRate,
  createEmployeeNote,
  getEmployeeNotes,
  updateEmployeeNote,
  deleteEmployeeNote,
  addUserSkill,
  getUserSkills,
  updateUserSkill,
  deleteUserSkill,
  searchSkills,
  getHats,
  getHat,
  createHat,
  updateHat,
  deleteHat,
  setHatPermissions,
  getPermissionMatrix,
  getPermissionKeys,
  getUserElevations,
  grantElevation,
  revokeElevation,
  revokeAllElevationsForJob,
  uploadEmployeeAvatar,
  uploadCertificationDocument,
  importEmployeesCSV,
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
} from './services/people-service';

// ── PTO ────────────────────────────────────────────────────────────
export {
  createPolicy as createPTOPolicy,
  getPolicy as getPTOPolicy,
  getActivePolicy as getActivePTOPolicy,
  listActivePolicies as listActivePTOPolicies,
  updatePolicy as updatePTOPolicy,
  deletePolicy as deletePTOPolicy,
  recordTransaction as recordPTOTransaction,
  getUserTransactions as getPTOUserTransactions,
  getCurrentBalance as getPTOCurrentBalance,
  recordUsage as recordPTOUsage,
  recordAccrual as recordPTOAccrual,
} from './services/pto-service';

// ── Reports ────────────────────────────────────────────────────────
export {
  createAnnotation,
  getAnnotations,
  updateAnnotation,
  deleteAnnotation,
  createShareToken,
  getShareTokenByValue,
  listShareTokens,
  deactivateShareToken,
  recordTokenAccess,
  createTemplate,
  listTemplates,
  updateTemplate,
  deleteTemplate,
  getPreBillingAllJobs,
  getPreBilling,
  getTimesheets,
  getLaborOverview,
  getProfitability,
  generateExport,
  generateBookkeeperExport,
  generateExportBundle,
  getPublicReport,
} from './services/report-service';

// ── Billing Periods ────────────────────────────────────────────────
export {
  createBillingPeriod,
  getBillingPeriod,
  listBillingPeriods,
  lockBillingPeriod,
  unlockBillingPeriod,
  updateBillingPeriod,
  deleteBillingPeriod,
  isDateLocked,
} from './services/billing-service';

// ── Contacts ───────────────────────────────────────────────────────
export {
  getCustomers,
  searchCustomers,
  getCustomer,
  createCustomer,
  updateCustomer,
  toggleCustomerActive,
  getCustomerContacts,
  addCustomerContact,
  getCustomerJobs,
  getGCs,
  searchGCs,
  getGC,
  createGC,
  updateGC,
  toggleGCActive,
  getGCContacts,
  addGCContact,
  getGCJobs,
  getSupplierContacts,
  addSupplierContact,
  searchDirectory,
  updateEntityContact,
  deleteEntityContact,
  getJobCustomers,
  linkCustomerToJob,
  unlinkCustomerFromJob,
  getJobGCs,
  linkGCToJob,
  unlinkGCFromJob,
  importCustomersCSV,
  importContractorsCSV,
  findDuplicateCustomers,
  mergeCustomers,
} from './services/contacts-service';

// ── Costs ──────────────────────────────────────────────────────────
export {
  getCompanySettings as getCostSettings,
  updateCompanySetting as updateCostSetting,
  getCostLayers,
  getCostHistory,
  getPartCostSummary,
  setCustomMargin,
  clearCustomMargin,
  enforceDefaultMargin,
  getSpendingSummary,
  getSpendingBySupplier,
  getSpendingByCategory,
  getSpendingByJob,
  getSpendingTrend,
  getJobCostRollup,
  getJobBudgetStatus,
  getPriceVarianceReport,
  getBudgetAlerts,
  getDailyReport,
} from './services/costs-service';

// ── Settings ───────────────────────────────────────────────────────
export {
  getTheme,
  updateTheme,
  getAllSettings,
  getSetting,
  updateSetting,
  getWarrantyLengthDays,
  updateWarrantyLengthDays,
  listCompanyProfiles,
  getCompanyProfile,
  createCompanyProfile,
  updateCompanyProfile,
  deleteCompanyProfile,
  getPDFSettings,
  updatePDFSettings,
  uploadCompanyLogo,
  getBillingCycle,
  updateBillingCycle,
  getPayPeriod,
  updatePayPeriod,
  getPayrollColumns,
  updatePayrollColumns,
} from './services/settings-service';

// ── Dashboard ──────────────────────────────────────────────────────
export {
  getDashboard,
  getFastDriveContext,
  startDrive,
  getCertAlerts,
  getVehicleExpiryAlerts,
} from './services/dashboard-service';

// ── Notifications ──────────────────────────────────────────────────
export {
  getNotificationBadge,
  listNotifications,
  markNotificationsRead,
  getNotificationPreferences,
  updateNotificationPreferences,
  getNotificationSoundSettings,
  updateNotificationSoundSettings,
  createNotification,
} from './services/notifications-service';

// ── Trailer ────────────────────────────────────────────────────────
export {
  createTrailer,
  getTrailer,
  listTrailers,
  updateTrailer,
  deleteTrailer,
  recordLocationEvent,
  getTrailerLocationHistory,
  getTrailerCurrentLocations,
} from './services/trailer-service';

// ── Attachments ────────────────────────────────────────────────────
export {
  createAttachment,
  getAttachment,
  getAttachmentsForEntity,
  getAttachmentCount,
  updateAttachment,
  deleteAttachment,
  getRecentAttachments,
} from './services/attachment-service';

// ── Receiving ──────────────────────────────────────────────────────
export {
  startSession as startReceivingSession,
  getSession as getReceivingSession,
  getSessionsForPO as getReceivingSessionsForPO,
  getActiveSessions as getActiveReceivingSessions,
  completeSession as completeReceivingSession,
  cancelSession as cancelReceivingSession,
  addSessionItem as addReceivingSessionItem,
  getSessionItems as getReceivingSessionItems,
  updateSessionItem as updateReceivingSessionItem,
  recordScan as recordReceivingScan,
} from './services/receiving-service';

// ── Supplier Portal ────────────────────────────────────────────────
export {
  createPortalToken,
  getPortalToken,
  validateToken as validatePortalToken,
  getTokensForSupplier,
  deactivateToken as deactivatePortalToken,
  deletePortalToken,
  createAcknowledgment,
  getAcknowledgment,
  getAcknowledgmentForPO,
  listRecentAcknowledgments,
  isPOAcknowledged,
} from './services/supplier-portal-service';

// ── Depreciation ───────────────────────────────────────────────────
export {
  createEntry as createDepreciationEntry,
  getToolSchedule as getDepreciationSchedule,
  getToolDepreciationSummary,
  generateSchedule as generateDepreciationSchedule,
  getEntriesByFiscalYear as getDepreciationByFiscalYear,
} from './services/depreciation-service';

// ── Security (device identity, encryption, BT auth) ───────────────
export {
  initialiseDeviceSecurity,
  getDbEncryptionKey,
  storeDeviceKeypair,
  getDevicePublicKey,
  storeCertificate,
  getStoredCertificate,
  isCertificateValid,
  getDeviceIdentity,
  getSyncAuthFields,
  createBtHello,
  clearDeviceSecurity,
  rotateDbEncryptionKey,
} from './services/security-service';
