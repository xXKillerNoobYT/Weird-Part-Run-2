/**
 * Local Client — implements the same API surface as the HTTP client
 * for Capacitor (offline) mode.
 *
 * Each method maps to an api/*.ts function but routes to the local
 * TypeScript service instead of making an HTTP request. The frontend
 * components don't know the difference — they call the same api
 * functions, which are routed here via the adapter when in Capacitor mode.
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
} from './services/notebook-service';

// ── Warehouse (read) ───────────────────────────────────────────────
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

// ── Parts (read-only) ──────────────────────────────────────────────
export {
  listParts,
  getPart,
  searchParts,
  getCategories,
  getPartTypes,
  getPartSuppliers,
} from './services/parts-service';

// ── Fleet (read-only) ──────────────────────────────────────────────
export {
  getMyVehicle,
  getVehicle,
  listVehicles,
  getVehicleAssignments,
  getTruckInventory,
} from './services/fleet-service';

// ── Scheduling (read-only) ─────────────────────────────────────────
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
