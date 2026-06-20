import Foundation
import GRDB

/// Jobs & Labor Service — full CRUD for jobs, labor/clock in-out, questionnaires,
/// one-time questions, daily reports, team members, job parts, and dashboard KPIs.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Jobs & Labor feature area (Phases 4, 4.5, 15)
public final class JobsService: Sendable {
    let db: AppDatabase
    private static let warehouseClockJobNumber = "__SHOP_WAREHOUSE__"
    private static let warehouseClockJobName = "Shop / Warehouse"

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum JobsError: Error, Sendable, Equatable {
        case jobNotFound(Int64)
        case jobNotClockable(Int64)
        case partNotFound(Int64)
        case userNotFound(Int64)
        case insufficientStagedMaterial(available: Int, requested: Int)
        case laborEntryNotFound(Int64)
        case alreadyClockedIn(userId: Int64, jobId: Int64)
        case notClockedIn(userId: Int64)
        case userNotActive(Int64)
        case questionNotFound(Int64)
        case requiredQuestionNotAnswered(Int64)
        case invalidReturnQuantity(Int64)
        case invalidAmount(Int64)
        case invalidDuration(Int64)
        case requiredFieldEmpty
        case invalidOvertimeSettings
        case templateNotFound(Int64)
        case stageNotFound(Int64)
        case stageInUse(Int64)
        case invalidStageTemplate(Int64)
        case invalidClockOutTime(laborEntryId: Int64)
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A job row for list views with summary counts.
    public struct JobListItem: Sendable, Identifiable {
        public let id: Int64
        public let jobNumber: String
        public let jobName: String
        public let customerName: String?
        public let status: String
        public let priority: String
        public let jobType: String
        public let stageTemplateId: Int64?
        public let teamCount: Int
        public let startDate: String?
        public let dueDate: String?
        public let currentStageId: Int64?
        public let estimatedHours: Double?
        public let budgetLimit: Double?
        public let laborHours: Double
        public let actualCost: Double

        public init(
            id: Int64, jobNumber: String, jobName: String, customerName: String?,
            status: String, priority: String, jobType: String = "service",
            stageTemplateId: Int64? = nil,
            teamCount: Int, startDate: String?, dueDate: String?,
            currentStageId: Int64? = nil,
            estimatedHours: Double? = nil,
            budgetLimit: Double? = nil,
            laborHours: Double = 0,
            actualCost: Double = 0
        ) {
            self.id = id
            self.jobNumber = jobNumber
            self.jobName = jobName
            self.customerName = customerName
            self.status = status
            self.priority = priority
            self.jobType = jobType
            self.stageTemplateId = stageTemplateId
            self.teamCount = teamCount
            self.startDate = startDate
            self.dueDate = dueDate
            self.currentStageId = currentStageId
            self.estimatedHours = estimatedHours
            self.budgetLimit = budgetLimit
            self.laborHours = laborHours
            self.actualCost = actualCost
        }
    }

    /// A job stage with its computed status relative to a job's progression.
    public struct JobStageStatus: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let sortOrder: Int
        /// "completed", "in_progress", or "pending"
        public let status: String

        public init(id: Int64, name: String, sortOrder: Int, status: String) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
            self.status = status
        }
    }

    /// Stage template metadata for configurable job workflows (GH #625 / WEI-2068).
    public struct JobStageTemplate: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let isDefault: Bool
        public let archivedAt: String?
        public let stageCount: Int
        /// Active, non-cancelled/non-completed jobs currently assigned to this template.
        public let activeJobCount: Int

        public init(id: Int64, name: String, isDefault: Bool, archivedAt: String?, stageCount: Int, activeJobCount: Int = 0) {
            self.id = id
            self.name = name
            self.isDefault = isDefault
            self.archivedAt = archivedAt
            self.stageCount = stageCount
            self.activeJobCount = activeJobCount
        }
    }

    /// Part-category automatic stage routing scoped to a stage template.
    public struct JobStageCategoryMapping: Sendable, Identifiable {
        public let id: Int64
        public let templateId: Int64
        public let categoryId: Int64
        public let categoryName: String
        public let stageId: Int64?
        public let stageName: String?

        public init(id: Int64, templateId: Int64, categoryId: Int64, categoryName: String, stageId: Int64?, stageName: String?) {
            self.id = id
            self.templateId = templateId
            self.categoryId = categoryId
            self.categoryName = categoryName
            self.stageId = stageId
            self.stageName = stageName
        }
    }

    /// One row from the staged job-stage template editor draft.
    /// A nil existingId creates a new stage; non-nil keeps/renames that stage.
    /// The array order supplied to applyJobStageTemplateDraft becomes sort_order.
    public struct JobStageTemplateDraftStage: Sendable, Equatable {
        public let existingId: Int64?
        public let name: String

        public init(existingId: Int64?, name: String) {
            self.existingId = existingId
            self.name = name
        }
    }

    /// Preview result for changing a job's stage template.
    public struct JobStageTemplateAssignmentPreview: Sendable {
        public let jobId: Int64
        public let currentTemplateId: Int64?
        public let nextTemplateId: Int64
        public let currentStageId: Int64?
        public let replacementStageId: Int64?
        public let preservesCurrentStage: Bool

        public init(jobId: Int64, currentTemplateId: Int64?, nextTemplateId: Int64, currentStageId: Int64?, replacementStageId: Int64?, preservesCurrentStage: Bool) {
            self.jobId = jobId
            self.currentTemplateId = currentTemplateId
            self.nextTemplateId = nextTemplateId
            self.currentStageId = currentStageId
            self.replacementStageId = replacementStageId
            self.preservesCurrentStage = preservesCurrentStage
        }
    }

    /// Timestamped notebook activity surfaced on the job detail screen.
    public struct JobNoteRow: Sendable, Identifiable {
        public let id: Int64
        public let title: String
        public let content: String?
        public let entryType: String
        public let authorId: Int64?
        public let authorName: String
        public let createdAt: String?

        public init(id: Int64, title: String, content: String?, entryType: String, authorId: Int64?, authorName: String, createdAt: String?) {
            self.id = id
            self.title = title
            self.content = content
            self.entryType = entryType
            self.authorId = authorId
            self.authorName = authorName
            self.createdAt = createdAt
        }
    }

    /// Inventory movement linked to a job through Stage 3 stock movement records.
    public struct JobInventoryMovementRow: Sendable, Identifiable {
        public let id: Int64
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let qty: Int
        public let movementType: String
        public let locationSummary: String
        public let reason: String?
        public let notes: String?
        public let performedByName: String
        public let createdAt: String?

        public init(
            id: Int64, partId: Int64, partName: String, partCode: String?,
            qty: Int, movementType: String, locationSummary: String,
            reason: String?, notes: String?, performedByName: String, createdAt: String?
        ) {
            self.id = id
            self.partId = partId
            self.partName = partName
            self.partCode = partCode
            self.qty = qty
            self.movementType = movementType
            self.locationSummary = locationSummary
            self.reason = reason
            self.notes = notes
            self.performedByName = performedByName
            self.createdAt = createdAt
        }
    }

    /// Material currently staged and ready to use on a job.
    public struct JobReadyMaterialRow: Sendable, Identifiable {
        public let id: Int64
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let stagedQty: Int
        public let sourceSummary: String
        public let lastMovedAt: String?

        public init(
            id: Int64, partId: Int64, partName: String, partCode: String?,
            stagedQty: Int, sourceSummary: String, lastMovedAt: String?
        ) {
            self.id = id
            self.partId = partId
            self.partName = partName
            self.partCode = partCode
            self.stagedQty = stagedQty
            self.sourceSummary = sourceSummary
            self.lastMovedAt = lastMovedAt
        }
    }

    public struct JobMaterialTotals: Sendable, Equatable {
        public let stagedQty: Int
        public let usedQty: Int
        /// Quantity credited back against consumed job material. Pending return
        /// handling is exposed separately through `pendingReturnQty`.
        public let returnedQty: Int
        public let pendingReturnQty: Int
        public let netMaterialCost: Double
        public let totalMaterialCost: Double

        public init(
            stagedQty: Int,
            usedQty: Int,
            returnedQty: Int,
            pendingReturnQty: Int,
            netMaterialCost: Double,
            totalMaterialCost: Double
        ) {
            self.stagedQty = stagedQty
            self.usedQty = usedQty
            self.returnedQty = returnedQty
            self.pendingReturnQty = pendingReturnQty
            self.netMaterialCost = netMaterialCost
            self.totalMaterialCost = totalMaterialCost
        }
    }

    public struct JobMaterialHistoryRow: Sendable, Identifiable {
        public let id: String
        public let eventType: String
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let qty: Int
        public let actorName: String
        public let locationSummary: String
        public let reference: String?
        public let notes: String?
        public let createdAt: String?

        public init(
            id: String,
            eventType: String,
            partId: Int64,
            partName: String,
            partCode: String?,
            qty: Int,
            actorName: String,
            locationSummary: String,
            reference: String?,
            notes: String?,
            createdAt: String?
        ) {
            self.id = id
            self.eventType = eventType
            self.partId = partId
            self.partName = partName
            self.partCode = partCode
            self.qty = qty
            self.actorName = actorName
            self.locationSummary = locationSummary
            self.reference = reference
            self.notes = notes
            self.createdAt = createdAt
        }
    }

    /// Full job detail with aggregated data.
    public struct JobDetail: Sendable {
        public let id: Int64
        public let jobNumber: String
        public let jobName: String
        public let customerName: String?
        public let addressLine1: String?
        public let addressLine2: String?
        public let city: String?
        public let state: String?
        public let zip: String?
        public let gpsLat: Double?
        public let gpsLng: Double?
        public let status: String
        public let priority: String
        public let jobType: String
        public let billRateTypeId: Int64?
        public let billingRate: Double?
        public let estimatedHours: Double?
        public let leadUserId: Int64?
        public let leadUserName: String?
        public let onCallType: String?
        public let warrantyStartDate: String?
        public let warrantyEndDate: String?
        public let startDate: String?
        public let dueDate: String?
        public let completedDate: String?
        public let notes: String?
        public let budgetLimit: Double?
        public let budgetAlertPercent: Double?
        public let createdBy: Int64?
        public let deletedAt: String?
        public let createdAt: String?
        public let updatedAt: String?
        public let teamCount: Int
        public let partsCost: Double
        public let laborHours: Double
        public let stageTemplateId: Int64?

        public init(
            id: Int64, jobNumber: String, jobName: String, customerName: String?,
            addressLine1: String?, addressLine2: String?, city: String?, state: String?, zip: String?,
            gpsLat: Double?, gpsLng: Double?,
            status: String, priority: String, jobType: String,
            billRateTypeId: Int64?, billingRate: Double?, estimatedHours: Double?,
            leadUserId: Int64?, leadUserName: String?, onCallType: String?,
            warrantyStartDate: String?, warrantyEndDate: String?,
            startDate: String?, dueDate: String?, completedDate: String?,
            notes: String?, budgetLimit: Double?, budgetAlertPercent: Double?,
            createdBy: Int64?, deletedAt: String?, createdAt: String?, updatedAt: String?,
            teamCount: Int, partsCost: Double, laborHours: Double, stageTemplateId: Int64? = nil
        ) {
            self.id = id
            self.jobNumber = jobNumber
            self.jobName = jobName
            self.customerName = customerName
            self.addressLine1 = addressLine1
            self.addressLine2 = addressLine2
            self.city = city
            self.state = state
            self.zip = zip
            self.gpsLat = gpsLat
            self.gpsLng = gpsLng
            self.status = status
            self.priority = priority
            self.jobType = jobType
            self.billRateTypeId = billRateTypeId
            self.billingRate = billingRate
            self.estimatedHours = estimatedHours
            self.leadUserId = leadUserId
            self.leadUserName = leadUserName
            self.onCallType = onCallType
            self.warrantyStartDate = warrantyStartDate
            self.warrantyEndDate = warrantyEndDate
            self.startDate = startDate
            self.dueDate = dueDate
            self.completedDate = completedDate
            self.notes = notes
            self.budgetLimit = budgetLimit
            self.budgetAlertPercent = budgetAlertPercent
            self.createdBy = createdBy
            self.deletedAt = deletedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.teamCount = teamCount
            self.partsCost = partsCost
            self.laborHours = laborHours
            self.stageTemplateId = stageTemplateId
        }
    }

    /// A labor entry row enriched with user and job names.
    public struct LaborEntryRow: Sendable, Identifiable {
        public let id: Int64
        public let userId: Int64
        public let userName: String
        public let jobId: Int64
        public let jobName: String
        public let clockIn: String
        public let clockOut: String?
        public let status: String
        public let regularHours: Double
        public let overtimeHours: Double
        public let gpsInLat: Double?
        public let gpsInLng: Double?
        public let gpsOutLat: Double?
        public let gpsOutLng: Double?
        public let linkedTodoId: Int64?
        public let workType: String?

        public init(
            id: Int64, userId: Int64, userName: String,
            jobId: Int64, jobName: String,
            clockIn: String, clockOut: String?, status: String,
            regularHours: Double, overtimeHours: Double,
            gpsInLat: Double?, gpsInLng: Double?,
            gpsOutLat: Double?, gpsOutLng: Double?,
            linkedTodoId: Int64? = nil, workType: String? = nil
        ) {
            self.id = id
            self.userId = userId
            self.userName = userName
            self.jobId = jobId
            self.jobName = jobName
            self.clockIn = clockIn
            self.clockOut = clockOut
            self.status = status
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
            self.gpsInLat = gpsInLat
            self.gpsInLng = gpsInLng
            self.gpsOutLat = gpsOutLat
            self.gpsOutLng = gpsOutLng
            self.linkedTodoId = linkedTodoId
            self.workType = workType
        }
    }

    /// Summary of labor for a job.
    public struct LaborSummary: Sendable {
        public let totalEntries: Int
        public let totalRegularHours: Double
        public let totalOvertimeHours: Double
        public let uniqueWorkers: Int

        public init(totalEntries: Int, totalRegularHours: Double, totalOvertimeHours: Double, uniqueWorkers: Int) {
            self.totalEntries = totalEntries
            self.totalRegularHours = totalRegularHours
            self.totalOvertimeHours = totalOvertimeHours
            self.uniqueWorkers = uniqueWorkers
        }
    }

    /// A clock-out questionnaire item with optional answer.
    public struct QuestionnaireItem: Sendable {
        public let questionId: Int64
        public let questionText: String
        public let answerType: String
        public let isRequired: Bool
        public let answer: String?

        public init(questionId: Int64, questionText: String, answerType: String, isRequired: Bool, answer: String?) {
            self.questionId = questionId
            self.questionText = questionText
            self.answerType = answerType
            self.isRequired = isRequired
            self.answer = answer
        }
    }

    /// A one-time question row with job and user names.
    public struct OneTimeQuestionRow: Sendable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String
        public let questionText: String
        public let status: String
        public let createdByName: String
        public let answerText: String?
        public let answeredByName: String?
        public let answeredAt: String?

        public init(
            id: Int64, jobId: Int64, jobName: String, questionText: String,
            status: String, createdByName: String,
            answerText: String?, answeredByName: String?, answeredAt: String?
        ) {
            self.id = id
            self.jobId = jobId
            self.jobName = jobName
            self.questionText = questionText
            self.status = status
            self.createdByName = createdByName
            self.answerText = answerText
            self.answeredByName = answeredByName
            self.answeredAt = answeredAt
        }
    }

    /// A daily report row for list views.
    public struct DailyReportRow: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String
        public let reportDate: String
        public let status: String
        public let reviewedByName: String?

        public init(id: Int64, jobId: Int64, jobName: String, reportDate: String, status: String, reviewedByName: String?) {
            self.id = id
            self.jobId = jobId
            self.jobName = jobName
            self.reportDate = reportDate
            self.status = status
            self.reviewedByName = reviewedByName
        }
    }

    /// A team member row with user name.
    public struct TeamMemberRow: Sendable, Identifiable {
        public let id: Int64
        public let userId: Int64
        public let userName: String
        public let role: String
        public let joinedAt: String?

        public init(id: Int64, userId: Int64, userName: String, role: String, joinedAt: String?) {
            self.id = id
            self.userId = userId
            self.userName = userName
            self.role = role
            self.joinedAt = joinedAt
        }
    }

    /// A job part row enriched with part name/code.
    public struct JobPartRow: Sendable, Identifiable {
        public let id: Int64
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let qtyConsumed: Int
        public let qtyReturned: Int
        public let unitCost: Double?
        public let unitSell: Double?

        public init(
            id: Int64, partId: Int64, partName: String, partCode: String?,
            qtyConsumed: Int, qtyReturned: Int, unitCost: Double?, unitSell: Double?
        ) {
            self.id = id
            self.partId = partId
            self.partName = partName
            self.partCode = partCode
            self.qtyConsumed = qtyConsumed
            self.qtyReturned = qtyReturned
            self.unitCost = unitCost
            self.unitSell = unitSell
        }
    }

    /// Dashboard KPIs for the jobs overview.
    public struct JobsDashboardKPIs: Sendable {
        public let activeJobs: Int
        public let clockedInUsers: Int
        public let todayLaborHours: Double
        public let overdueJobs: Int

        public init(activeJobs: Int, clockedInUsers: Int, todayLaborHours: Double, overdueJobs: Int) {
            self.activeJobs = activeJobs
            self.clockedInUsers = clockedInUsers
            self.todayLaborHours = todayLaborHours
            self.overdueJobs = overdueJobs
        }
    }

    /// Job stats summary (active/completed/total).
    public struct JobStats: Sendable {
        public let active: Int
        public let completed: Int
        public let total: Int

        public init(active: Int, completed: Int, total: Int) {
            self.active = active
            self.completed = completed
            self.total = total
        }
    }

    // =========================================================================
    // MARK: - 1. Job CRUD
    // =========================================================================

    /// List jobs with optional search and status filter.
    public func listJobs(
        search: String? = nil,
        status: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> [JobListItem] {
        do {
            return try db.writer.read { dbConn -> [JobListItem] in
                var whereClauses = ["j.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(j.job_name LIKE ? OR j.job_number LIKE ? OR j.customer_name LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }
                if let status, !status.isEmpty {
                    whereClauses.append("j.status = ?")
                    args.append(status)
                }

                args.append(limit)
                args.append(offset)

                let sql = """
                    WITH team_counts AS (
                        SELECT jtm.job_id, COUNT(*) AS team_count
                        FROM job_team_members jtm
                        WHERE jtm.deleted_at IS NULL
                        GROUP BY jtm.job_id
                    ),
                    labor_totals AS (
                        SELECT le.job_id,
                               SUM(le.regular_hours + le.overtime_hours) AS labor_hours,
                               SUM(
                                   le.regular_hours * COALESCE(u.pay_rate, 0)
                                   + le.overtime_hours * COALESCE(u.pay_rate, 0) * 1.5
                               ) AS labor_cost
                        FROM labor_entries le
                        LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                        WHERE le.deleted_at IS NULL
                          AND le.status = 'completed'
                        GROUP BY le.job_id
                    ),
                    po_costs AS (
                        SELECT jpo.job_id,
                               SUM(
                                   pli.qty_ordered * COALESCE(pli.received_unit_cost, pli.unit_cost, 0)
                               ) AS po_cost
                        FROM po_line_items pli
                        JOIN purchase_orders po ON po.id = pli.po_id
                        JOIN jpo_line_items jli ON jli.id = pli.jpo_line_id
                        JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id
                        WHERE pli.deleted_at IS NULL
                          AND jli.deleted_at IS NULL
                          AND jpo.deleted_at IS NULL
                          AND po.deleted_at IS NULL
                          AND po.status NOT IN ('cancelled')
                        GROUP BY jpo.job_id
                    )
                    SELECT j.id, j.job_number, j.job_name, j.customer_name,
                           j.status, j.priority, j.job_type, j.stage_template_id, j.start_date, j.due_date,
                           j.current_stage_id, j.estimated_hours, j.budget_limit,
                           COALESCE(tc.team_count, 0) AS team_count,
                           COALESCE(lt.labor_hours, 0) AS labor_hours,
                           COALESCE(lt.labor_cost, 0) + COALESCE(pc.po_cost, 0) AS actual_cost
                    FROM jobs j
                    LEFT JOIN team_counts tc ON tc.job_id = j.id
                    LEFT JOIN labor_totals lt ON lt.job_id = j.id
                    LEFT JOIN po_costs pc ON pc.job_id = j.id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY j.created_at DESC
                    LIMIT ? OFFSET ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    JobListItem(
                        id: row["id"] ?? 0,
                        jobNumber: row["job_number"] ?? "",
                        jobName: row["job_name"] ?? "",
                        customerName: row["customer_name"] as String?,
                        status: row["status"] ?? "active",
                        priority: row["priority"] ?? "normal",
                        jobType: row["job_type"] ?? "service",
                        stageTemplateId: row["stage_template_id"] as Int64?,
                        teamCount: row["team_count"] ?? 0,
                        startDate: row["start_date"] as String?,
                        dueDate: row["due_date"] as String?,
                        currentStageId: row["current_stage_id"] as Int64?,
                        estimatedHours: row["estimated_hours"] as Double?,
                        budgetLimit: row["budget_limit"] as Double?,
                        laborHours: row["labor_hours"] ?? 0,
                        actualCost: row["actual_cost"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single job by ID with full detail and aggregated data.
    public func getJob(id: Int64) throws -> JobDetail {
        let result: JobDetail? = try db.writer.read { dbConn -> JobDetail? in
            let sql = """
                SELECT j.*,
                       COALESCE(u.display_name, u.email, 'Unknown') AS lead_user_name,
                       COALESCE((SELECT COUNT(*) FROM job_team_members jtm
                                 WHERE jtm.job_id = j.id AND jtm.deleted_at IS NULL), 0) AS team_count,
                       COALESCE((SELECT SUM(jp.qty_consumed * COALESCE(jp.unit_cost_at_consume, 0))
                                 FROM job_parts jp
                                 WHERE jp.job_id = j.id AND jp.deleted_at IS NULL), 0) AS parts_cost,
                       COALESCE((SELECT SUM(le.regular_hours + le.overtime_hours)
                                 FROM labor_entries le
                                 WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0) AS labor_hours
                FROM jobs j
                LEFT JOIN users u ON u.id = j.lead_user_id AND u.deleted_at IS NULL
                WHERE j.id = ? AND j.deleted_at IS NULL
                """
            guard let row = try Row.fetchOne(dbConn, sql: sql, arguments: [id]) else {
                return nil
            }

            return JobDetail(
                id: row["id"] ?? 0,
                jobNumber: row["job_number"] ?? "",
                jobName: row["job_name"] ?? "",
                customerName: row["customer_name"] as String?,
                addressLine1: row["address_line1"] as String?,
                addressLine2: row["address_line2"] as String?,
                city: row["city"] as String?,
                state: row["state"] as String?,
                zip: row["zip"] as String?,
                gpsLat: row["gps_lat"] as Double?,
                gpsLng: row["gps_lng"] as Double?,
                status: row["status"] ?? "active",
                priority: row["priority"] ?? "normal",
                jobType: row["job_type"] ?? "service",
                billRateTypeId: row["bill_rate_type_id"] as Int64?,
                billingRate: row["billing_rate"] as Double?,
                estimatedHours: row["estimated_hours"] as Double?,
                leadUserId: row["lead_user_id"] as Int64?,
                leadUserName: row["lead_user_name"] as String?,
                onCallType: row["on_call_type"] as String?,
                warrantyStartDate: row["warranty_start"] as String?,
                warrantyEndDate: row["warranty_end"] as String?,
                startDate: row["start_date"] as String?,
                dueDate: row["due_date"] as String?,
                completedDate: row["completed_date"] as String?,
                notes: row["notes"] as String?,
                budgetLimit: row["budget_limit"] as Double?,
                budgetAlertPercent: row["budget_alert_percent"] as Double?,
                createdBy: row["created_by"] as Int64?,
                deletedAt: row["deleted_at"] as String?,
                createdAt: row["created_at"] as String?,
                updatedAt: row["updated_at"] as String?,
                teamCount: row["team_count"] ?? 0,
                partsCost: row["parts_cost"] ?? 0.0,
                laborHours: row["labor_hours"] ?? 0.0,
                stageTemplateId: row["stage_template_id"] as Int64?
            )
        }
        guard let result else { throw JobsError.jobNotFound(id) }
        return result
    }

    /// Create a new job. Returns the inserted row ID.
    @discardableResult
    public func createJob(
        jobNumber: String,
        jobName: String,
        customerName: String? = nil,
        addressLine1: String? = nil,
        addressLine2: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil,
        status: String = "active",
        priority: String = "normal",
        jobType: String = "service",
        billRateTypeId: Int64? = nil,
        billingRate: Double? = nil,
        estimatedHours: Double? = nil,
        leadUserId: Int64? = nil,
        onCallType: String? = nil,
        warrantyStartDate: String? = nil,
        warrantyEndDate: String? = nil,
        startDate: String? = nil,
        dueDate: String? = nil,
        notes: String? = nil,
        budgetLimit: Double? = nil,
        budgetAlertPercent: Double? = nil,
        createdBy: Int64? = nil,
        jobClassification: String = "standard"
    ) throws -> Int64 {
        guard !jobName.trimmingCharacters(in: .whitespaces).isEmpty else { throw JobsError.requiredFieldEmpty }
        guard !jobNumber.trimmingCharacters(in: .whitespaces).isEmpty else { throw JobsError.requiredFieldEmpty }
        let notebooks = NotebooksService(db: db)
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO jobs
                    (job_number, job_name, customer_name,
                     address_line1, address_line2, city, state, zip,
                     gps_lat, gps_lng, status, priority, job_type,
                     bill_rate_type_id, billing_rate, estimated_hours,
                     lead_user_id, on_call_type,
                     warranty_start, warranty_end,
                     start_date, due_date, notes,
                     budget_limit, budget_alert_percent, created_by,
                     job_classification,
                     created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                    """,
                arguments: [
                    jobNumber, jobName, customerName,
                    addressLine1, addressLine2, city, state, zip,
                    gpsLat, gpsLng, status, priority, jobType,
                    billRateTypeId, billingRate, estimatedHours,
                    leadUserId, onCallType,
                    warrantyStartDate, warrantyEndDate,
                    startDate, dueDate, notes,
                    budgetLimit, budgetAlertPercent, createdBy,
                    jobClassification
                ]
            )
            let jobId = dbConn.lastInsertedRowID
            try Self.ensureJobStableId(dbConn: dbConn, jobId: jobId)
            if let defaultTemplateId = try Int64.fetchOne(dbConn, sql: """
                SELECT id FROM job_stage_templates
                WHERE is_default = 1 AND archived_at IS NULL
                ORDER BY id ASC LIMIT 1
                """) {
                try dbConn.execute(sql: "UPDATE jobs SET stage_template_id = ? WHERE id = ?", arguments: [defaultTemplateId, jobId])
            }
            // Resolve notebook creator: prefer explicit createdBy, then first active user, then fallback to 1
            // so that notebook auto-creation is never silently skipped (fixes #626)
            let notebookCreatorId: Int64
            if let createdBy {
                notebookCreatorId = createdBy
            } else if let firstUser = try Int64.fetchOne(dbConn, sql: """
                    SELECT id FROM users
                    WHERE deleted_at IS NULL
                    ORDER BY id ASC LIMIT 1
                    """) {
                notebookCreatorId = firstUser
            } else {
                notebookCreatorId = 1
            }
            _ = try notebooks.ensureJobNotebook(
                dbConn: dbConn,
                jobId: jobId,
                jobName: jobName,
                jobType: jobType,
                createdBy: notebookCreatorId
            )
            if let initialNote = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !initialNote.isEmpty {
                _ = try Self.insertJobNotebookEntry(
                    dbConn,
                    jobId: jobId,
                    title: "Initial job note",
                    content: initialNote,
                    entryType: "note",
                    createdBy: notebookCreatorId
                )
            }
            return jobId
        }
    }

    /// Update an existing job. Only non-nil fields are updated.
    public func updateJob(
        id: Int64,
        jobName: String? = nil,
        customerName: String? = nil,
        addressLine1: String? = nil,
        addressLine2: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil,
        status: String? = nil,
        priority: String? = nil,
        jobType: String? = nil,
        billRateTypeId: Int64? = nil,
        billingRate: Double? = nil,
        estimatedHours: Double? = nil,
        leadUserId: Int64? = nil,
        onCallType: String? = nil,
        warrantyStartDate: String? = nil,
        warrantyEndDate: String? = nil,
        startDate: String? = nil,
        dueDate: String? = nil,
        completedDate: String? = nil,
        notes: String? = nil,
        budgetLimit: Double? = nil,
        budgetAlertPercent: Double? = nil
    ) throws {
        if let jobName, jobName.trimmingCharacters(in: .whitespaces).isEmpty {
            throw JobsError.requiredFieldEmpty
        }
        if let status, status.trimmingCharacters(in: .whitespaces).isEmpty {
            throw JobsError.requiredFieldEmpty
        }
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let jobName { setClauses.append("job_name = ?"); args.append(jobName) }
            if let customerName { setClauses.append("customer_name = ?"); args.append(customerName) }
            if let addressLine1 { setClauses.append("address_line1 = ?"); args.append(addressLine1) }
            if let addressLine2 { setClauses.append("address_line2 = ?"); args.append(addressLine2) }
            if let city { setClauses.append("city = ?"); args.append(city) }
            if let state { setClauses.append("state = ?"); args.append(state) }
            if let zip { setClauses.append("zip = ?"); args.append(zip) }
            if let gpsLat { setClauses.append("gps_lat = ?"); args.append(gpsLat) }
            if let gpsLng { setClauses.append("gps_lng = ?"); args.append(gpsLng) }
            if let status { setClauses.append("status = ?"); args.append(status) }
            if let priority { setClauses.append("priority = ?"); args.append(priority) }
            if let jobType { setClauses.append("job_type = ?"); args.append(jobType) }
            if let billRateTypeId { setClauses.append("bill_rate_type_id = ?"); args.append(billRateTypeId) }
            if let billingRate { setClauses.append("billing_rate = ?"); args.append(billingRate) }
            if let estimatedHours { setClauses.append("estimated_hours = ?"); args.append(estimatedHours) }
            if let leadUserId { setClauses.append("lead_user_id = ?"); args.append(leadUserId) }
            if let onCallType { setClauses.append("on_call_type = ?"); args.append(onCallType) }
            if let warrantyStartDate { setClauses.append("warranty_start = ?"); args.append(warrantyStartDate) }
            if let warrantyEndDate { setClauses.append("warranty_end = ?"); args.append(warrantyEndDate) }
            if let startDate { setClauses.append("start_date = ?"); args.append(startDate) }
            if let dueDate { setClauses.append("due_date = ?"); args.append(dueDate) }
            if let completedDate { setClauses.append("completed_date = ?"); args.append(completedDate) }
            if let notes { setClauses.append("notes = ?"); args.append(notes) }
            if let budgetLimit { setClauses.append("budget_limit = ?"); args.append(budgetLimit) }
            if let budgetAlertPercent { setClauses.append("budget_alert_percent = ?"); args.append(budgetAlertPercent) }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE jobs SET \(setClauses.joined(separator: ", ")) WHERE id = ? AND deleted_at IS NULL"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Add a timestamped, attributed note to the job notebook.
    @discardableResult
    public func addJobNote(jobId: Int64, title: String, content: String? = nil, createdBy: Int64) throws -> Int64 {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { throw JobsError.requiredFieldEmpty }
        return try db.writer.write { dbConn in
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL", arguments: [jobId]) ?? 0 > 0 else {
                throw JobsError.jobNotFound(jobId)
            }
            return try Self.insertJobNotebookEntry(
                dbConn,
                jobId: jobId,
                title: cleanedTitle,
                content: content,
                entryType: "note",
                createdBy: createdBy
            )
        }
    }

    /// List job notebook notes and stage-change audit entries in newest-first order.
    public func listJobNotes(jobId: Int64, limit: Int = 25) throws -> [JobNoteRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT ne.id, ne.title, ne.content, ne.entry_type, ne.created_by, ne.created_at,
                           COALESCE(u.display_name, u.email, 'User #' || ne.created_by) AS author_name
                    FROM notebook_entries ne
                    JOIN notebook_sections ns ON ns.id = ne.section_id AND ns.deleted_at IS NULL
                    JOIN notebooks n ON n.id = ns.notebook_id AND n.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = ne.created_by AND u.deleted_at IS NULL
                    WHERE n.job_id = ?
                      AND ne.deleted_at IS NULL
                      AND COALESCE(ne.is_deleted, 0) = 0
                      AND ne.entry_type IN ('note', 'stage_change')
                    ORDER BY ne.created_at DESC, ne.id DESC
                    LIMIT ?
                    """, arguments: [jobId, max(1, limit)])
                return rows.map { row in
                    JobNoteRow(
                        id: row["id"] ?? 0,
                        title: row["title"] ?? "",
                        content: row["content"],
                        entryType: row["entry_type"] ?? "note",
                        authorId: row["created_by"],
                        authorName: row["author_name"] ?? "Unknown",
                        createdAt: row["created_at"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) { return [] }
            throw error
        }
    }

    /// List stock movements linked to the job by Stage 3 inventory workflows.
    public func listJobInventoryMovements(jobId: Int64, limit: Int = 25) throws -> [JobInventoryMovementRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT sm.id, sm.part_id, sm.qty, sm.movement_type,
                           sm.from_location_type, sm.to_location_type,
                           sm.reason, sm.notes, sm.created_at,
                           p.name AS part_name, p.code AS part_code,
                           COALESCE(u.display_name, u.email, 'User #' || sm.performed_by) AS performed_by_name
                    FROM stock_movements sm
                    LEFT JOIN parts p ON p.id = sm.part_id AND p.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = sm.performed_by AND u.deleted_at IS NULL
                    WHERE sm.job_id = ? AND sm.deleted_at IS NULL
                    ORDER BY sm.created_at DESC, sm.id DESC
                    LIMIT ?
                    """, arguments: [jobId, max(1, limit)])
                return rows.map { row in
                    let from: String = row["from_location_type"] ?? "Unknown"
                    let to: String = row["to_location_type"] ?? "Unknown"
                    return JobInventoryMovementRow(
                        id: row["id"] ?? 0,
                        partId: row["part_id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown Part",
                        partCode: row["part_code"],
                        qty: row["qty"] ?? 0,
                        movementType: row["movement_type"] ?? "movement",
                        locationSummary: "\(from.capitalized) -> \(to.capitalized)",
                        reason: row["reason"],
                        notes: row["notes"],
                        performedByName: row["performed_by_name"] ?? "Unknown",
                        createdAt: row["created_at"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get aggregate job statistics: active, completed, total counts.
    public func getJobStats() throws -> JobStats {
        let active = try safeCount(
            sql: "SELECT COUNT(*) FROM jobs WHERE status = 'active' AND deleted_at IS NULL"
        )
        let completed = try safeCount(
            sql: "SELECT COUNT(*) FROM jobs WHERE status = 'completed' AND deleted_at IS NULL"
        )
        let total = try safeCount(
            sql: "SELECT COUNT(*) FROM jobs WHERE deleted_at IS NULL"
        )
        return JobStats(active: active, completed: completed, total: total)
    }

    /// Get jobs linked to a specific customer via the `job_customers` join table.
    public func getJobsForCustomer(customerId: Int64) throws -> [JobListItem] {
        do {
            return try db.writer.read { dbConn -> [JobListItem] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT j.id, j.job_number, j.job_name, j.customer_name,
                               j.status, j.priority, j.job_type, j.start_date, j.due_date,
                               COALESCE((SELECT COUNT(*) FROM job_team_members jtm
                                         WHERE jtm.job_id = j.id AND jtm.deleted_at IS NULL), 0) AS team_count
                        FROM jobs j
                        INNER JOIN job_customers jc ON jc.job_id = j.id AND jc.deleted_at IS NULL
                        WHERE jc.customer_id = ? AND j.deleted_at IS NULL
                        ORDER BY j.created_at DESC
                        """,
                    arguments: [customerId]
                )
                return rows.map { row in
                    JobListItem(
                        id: row["id"] ?? 0,
                        jobNumber: row["job_number"] ?? "",
                        jobName: row["job_name"] ?? "",
                        customerName: row["customer_name"] as String?,
                        status: row["status"] ?? "active",
                        priority: row["priority"] ?? "normal",
                        jobType: row["job_type"] ?? "service",
                        teamCount: row["team_count"] ?? 0,
                        startDate: row["start_date"] as String?,
                        dueDate: row["due_date"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 1b. Warranty Tracking
    // =========================================================================

    /// Set warranty period for a job. Calculates end date from start + duration.
    public func setWarranty(jobId: Int64, startDate: Date, durationDays: Int) throws {
        guard durationDays > 0 else { throw JobsError.invalidDuration(jobId) }
        let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: startDate) ?? startDate.addingTimeInterval(Double(durationDays) * 86400)
        let startStr = CoreFormatters.iso8601.string(from: startDate)
        let endStr = CoreFormatters.iso8601.string(from: endDate)

        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE jobs SET
                    warranty_start = ?,
                    warranty_end = ?,
                    warranty_duration_days = ?,
                    status = 'warranty',
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [startStr, endStr, durationDays, jobId])
        }
    }

    /// Check if warranty is currently active for a job.
    public func isWarrantyActive(jobId: Int64) throws -> Bool {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT warranty_end FROM jobs WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId])
            guard let endStr = row?["warranty_end"] as? String else { return false }
            guard let endDate = CoreFormatters.parseISO(endStr) else { return false }
            return endDate > Date()
        }
    }

    /// Get number of warranty days remaining for a job. Returns nil if no warranty set.
    public func warrantyDaysRemaining(jobId: Int64) throws -> Int? {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT warranty_end FROM jobs WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId])
            guard let endStr = row?["warranty_end"] as? String else { return nil }
            guard let endDate = CoreFormatters.parseISO(endStr) else { return nil }
            return Calendar.current.dateComponents([.day], from: Date(), to: endDate).day
        }
    }

    // =========================================================================
    // MARK: - 1c. Payment Hold
    // =========================================================================

    /// Put a job on payment hold. Blocks clock-in for all workers.
    public func setPaymentHold(jobId: Int64, amount: Double, reason: String?) throws {
        guard amount > 0 else { throw JobsError.invalidAmount(jobId) }
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE jobs SET
                    status = 'payment_hold',
                    payment_hold_amount = ?,
                    payment_hold_date = datetime('now'),
                    payment_hold_reason = ?,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [amount, reason, jobId])
        }
    }

    /// Remove payment hold from a job, returning it to active status.
    public func removePaymentHold(jobId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE jobs SET
                    status = 'active',
                    payment_hold_amount = NULL,
                    payment_hold_date = NULL,
                    payment_hold_reason = NULL,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId])
        }
    }

    /// Check if a job is on payment hold. Used to block clock-in.
    public func isJobOnPaymentHold(jobId: Int64) throws -> Bool {
        try db.writer.read { dbConn in
            let count = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM jobs
                WHERE id = ? AND status = 'payment_hold' AND deleted_at IS NULL
                """, arguments: [jobId]) ?? 0
            return count > 0
        }
    }

    // =========================================================================
    // MARK: - 1d. Continuous Jobs
    // =========================================================================

    /// Schedule data for continuous/recurring jobs.
    public struct ContinuousSchedule: Codable, Sendable {
        public let daysOfWeek: [Int]  // 1=Mon, 7=Sun
        public let frequency: String   // "weekly", "biweekly", "monthly"

        public init(daysOfWeek: [Int], frequency: String) {
            self.daysOfWeek = daysOfWeek
            self.frequency = frequency
        }
    }

    /// Mark a job as continuous with an optional schedule.
    public func setJobContinuous(jobId: Int64, schedule: ContinuousSchedule?) throws {
        let scheduleJSON: String?
        if let schedule {
            let data = try JSONEncoder().encode(schedule)
            scheduleJSON = String(data: data, encoding: .utf8)
        } else {
            scheduleJSON = nil
        }

        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE jobs SET
                    is_continuous = 1,
                    job_classification = 'continuous',
                    continuous_schedule = ?,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [scheduleJSON, jobId])
        }
    }

    /// Get all continuous jobs for a user (jobs they're assigned to that are continuous).
    public func getContinuousJobs(userId: Int64) throws -> [JobListItem] {
        do {
            return try db.writer.read { dbConn -> [JobListItem] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT j.id, j.job_number, j.job_name,
                           j.customer_name,
                           j.status, j.priority, j.job_type,
                           (SELECT COUNT(*) FROM job_team_members WHERE job_id = j.id AND deleted_at IS NULL) AS team_count,
                           j.start_date, j.due_date
                    FROM jobs j
                    INNER JOIN job_team_members tm ON tm.job_id = j.id AND tm.user_id = ? AND tm.deleted_at IS NULL
                    WHERE j.is_continuous = 1 AND j.deleted_at IS NULL
                    ORDER BY j.job_name ASC
                    """, arguments: [userId])
                return rows.map { row in
                    JobListItem(
                        id: row["id"] ?? 0,
                        jobNumber: row["job_number"] ?? "",
                        jobName: row["job_name"] ?? "",
                        customerName: row["customer_name"] as String?,
                        status: row["status"] ?? "active",
                        priority: row["priority"] ?? "normal",
                        jobType: row["job_type"] ?? "service",
                        teamCount: row["team_count"] ?? 0,
                        startDate: row["start_date"] as String?,
                        dueDate: row["due_date"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Labor / Clock In-Out
    // =========================================================================

    /// Clock a user into a job. Creates a new labor entry with status 'clocked_in'.
    ///
    /// - Throws: `JobsError.alreadyClockedIn` if the user already has an open entry.
    /// - Returns: The new labor entry row ID.
    @discardableResult
    public func clockIn(
        userId: Int64,
        jobId: Int64,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil
    ) throws -> Int64 {
        try clockIn(userId: userId, jobId: jobId, at: Date(), gpsLat: gpsLat, gpsLng: gpsLng)
    }

    /// Deterministic clock-in variant for imported time entries, tests, and job-switch flows.
    @discardableResult
    public func clockIn(
        userId: Int64,
        jobId: Int64,
        at clockInAt: Date,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil
    ) throws -> Int64 {
        let clockInTimestamp = Self.sqliteTimestamp(clockInAt)
        return try db.writer.write { dbConn in
            try Self.createClockEntry(
                dbConn: dbConn,
                userId: userId,
                jobId: jobId,
                clockInTimestamp: clockInTimestamp,
                gpsLat: gpsLat,
                gpsLng: gpsLng
            )
        }
    }

    /// Clock a user into the internal Shop / Warehouse time bucket.
    ///
    /// The labor_entries schema requires a job_id, while the iOS clock page
    /// exposes Shop / Warehouse as a pinned non-job option. This method bridges
    /// that gap by creating/reusing a hidden active job row that is not shown in
    /// the normal clock job picker, then creating the labor entry against it.
    @discardableResult
    public func clockInToWarehouse(
        userId: Int64,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil
    ) throws -> Int64 {
        try clockInToWarehouse(userId: userId, at: Date(), gpsLat: gpsLat, gpsLng: gpsLng)
    }

    /// Deterministic Shop / Warehouse clock-in variant.
    @discardableResult
    public func clockInToWarehouse(
        userId: Int64,
        at clockInAt: Date,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil
    ) throws -> Int64 {
        let clockInTimestamp = Self.sqliteTimestamp(clockInAt)
        return try db.writer.write { dbConn in
            let existing = try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*) FROM labor_entries
                    WHERE user_id = ? AND status = 'clocked_in' AND deleted_at IS NULL
                    """,
                arguments: [userId]
            ) ?? 0

            if existing > 0 {
                throw JobsError.alreadyClockedIn(userId: userId, jobId: 0)
            }

            let warehouseJobId = try Self.ensureWarehouseClockJob(dbConn: dbConn, createdBy: userId)
            try dbConn.execute(
                sql: """
                    INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_in_gps_lat, clock_in_gps_lng, status, created_at)
                    VALUES (?, ?, ?, ?, ?, 'clocked_in', ?)
                    """,
                arguments: [userId, warehouseJobId, clockInTimestamp, gpsLat, gpsLng, clockInTimestamp]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Clock out a labor entry. Updates clock_out time, calculates hours, sets status to 'completed'.
    ///
    /// - Returns: The updated labor entry row ID.
    @discardableResult
    public func clockOut(
        laborEntryId: Int64,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil
    ) throws -> Int64 {
        try clockOut(laborEntryId: laborEntryId, at: Date(), gpsLat: gpsLat, gpsLng: gpsLng)
    }

    /// Deterministic clock-out variant. Calculates unpaid-break-adjusted regular/overtime
    /// hours against the user's local-day total before this entry.
    @discardableResult
    public func clockOut(
        laborEntryId: Int64,
        at clockOutAt: Date,
        gpsLat: Double? = nil,
        gpsLng: Double? = nil
    ) throws -> Int64 {
        let clockOutTimestamp = Self.sqliteTimestamp(clockOutAt)
        return try db.writer.write { dbConn in
            try Self.completeClockEntry(
                dbConn: dbConn,
                laborEntryId: laborEntryId,
                clockOutTimestamp: clockOutTimestamp,
                gpsLat: gpsLat,
                gpsLng: gpsLng
            )
        }
    }

    /// Close the user's current entry at `switchedAt`, then clock into `nextJobId` at the
    /// same instant. Both writes happen atomically so job switches cannot leave a gap or two
    /// active entries.
    @discardableResult
    public func switchClockedInJob(
        userId: Int64,
        nextJobId: Int64,
        at switchedAt: Date,
        clockOutGpsLat: Double? = nil,
        clockOutGpsLng: Double? = nil,
        clockInGpsLat: Double? = nil,
        clockInGpsLng: Double? = nil
    ) throws -> Int64 {
        let switchTimestamp = Self.sqliteTimestamp(switchedAt)
        return try db.writer.write { dbConn in
            guard let active = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT id
                    FROM labor_entries
                    WHERE user_id = ? AND status = 'clocked_in' AND deleted_at IS NULL
                    LIMIT 1
                    """,
                arguments: [userId]
            ) else {
                throw JobsError.notClockedIn(userId: userId)
            }
            let activeEntryId: Int64 = active["id"] ?? 0

            try Self.completeClockEntry(
                dbConn: dbConn,
                laborEntryId: activeEntryId,
                clockOutTimestamp: switchTimestamp,
                gpsLat: clockOutGpsLat,
                gpsLng: clockOutGpsLng
            )
            return try Self.createClockEntry(
                dbConn: dbConn,
                userId: userId,
                jobId: nextJobId,
                clockInTimestamp: switchTimestamp,
                gpsLat: clockInGpsLat,
                gpsLng: clockInGpsLng
            )
        }
    }

    public func getOvertimeSettings() throws -> OvertimeSettings {
        try db.writer.read { dbConn in
            try Self.fetchOvertimeSettings(dbConn)
        }
    }

    public func updateOvertimeSettings(
        calculationRule: String,
        dailyThresholdHours: Double = 8.0,
        weeklyThresholdHours: Double? = nil,
        weekStartWeekday: Int = 2,
        updatedBy: Int64? = nil
    ) throws -> OvertimeSettings {
        guard ["daily_only", "weekly_only", "daily_and_weekly"].contains(calculationRule),
              dailyThresholdHours > 0,
              weeklyThresholdHours.map({ $0 > 0 }) ?? true,
              (1...7).contains(weekStartWeekday)
        else {
            throw JobsError.invalidOvertimeSettings
        }

        let timestamp = Self.sqliteTimestamp(Date())
        return try db.writer.write { dbConn in
            if let updatedBy {
                try Self.requireActiveUser(dbConn, userId: updatedBy)
            }
            let existingId = try Int64.fetchOne(dbConn, sql: "SELECT id FROM overtime_settings ORDER BY id LIMIT 1")
            if let existingId {
                try dbConn.execute(sql: """
                    UPDATE overtime_settings
                    SET calculation_rule = ?,
                        daily_threshold_hours = ?,
                        weekly_threshold_hours = ?,
                        week_start_weekday = ?,
                        updated_by = ?,
                        updated_at = ?
                    WHERE id = ?
                    """, arguments: [
                    calculationRule, dailyThresholdHours, weeklyThresholdHours,
                    weekStartWeekday, updatedBy, timestamp, existingId
                ])
            } else {
                try dbConn.execute(sql: """
                    INSERT INTO overtime_settings
                        (calculation_rule, daily_threshold_hours, weekly_threshold_hours,
                         week_start_weekday, updated_by, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [
                    calculationRule, dailyThresholdHours, weeklyThresholdHours,
                    weekStartWeekday, updatedBy, timestamp
                ])
            }
            return try Self.fetchOvertimeSettings(dbConn)
        }
    }

    @discardableResult
    public func correctLaborEntry(
        laborEntryId: Int64,
        correctedBy: Int64,
        reason: String,
        clockIn: Date,
        clockOut: Date?
    ) throws -> Int64 {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw JobsError.requiredFieldEmpty }

        let newClockIn = Self.sqliteTimestamp(clockIn)
        let newClockOut = clockOut.map(Self.sqliteTimestamp(_:))
        if let clockOut, clockOut < clockIn {
            throw JobsError.invalidClockOutTime(laborEntryId: laborEntryId)
        }

        return try db.writer.write { dbConn in
            try Self.requireActiveUser(dbConn, userId: correctedBy)
            guard let oldEntry = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT id, user_id, clock_in, clock_out, regular_hours,
                           overtime_hours, status
                    FROM labor_entries
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [laborEntryId]
            ) else {
                throw JobsError.laborEntryNotFound(laborEntryId)
            }

            let userId: Int64 = oldEntry["user_id"] ?? 0
            let oldClockIn: String = oldEntry["clock_in"] ?? ""
            let oldClockOut: String? = oldEntry["clock_out"] as String?
            let oldRegularHours: Double = oldEntry["regular_hours"] ?? 0
            let oldOvertimeHours: Double = oldEntry["overtime_hours"] ?? 0
            let oldStatus: String = oldEntry["status"] ?? ""

            let allocation: (regular: Double, overtime: Double)
            let newStatus: String
            if let newClockOut {
                let rawHours = try Double.fetchOne(dbConn, sql: """
                    SELECT ROUND((julianday(?) - julianday(?)) * 24, 4)
                    """, arguments: [newClockOut, newClockIn]) ?? 0
                guard rawHours >= 0 else {
                    throw JobsError.invalidClockOutTime(laborEntryId: laborEntryId)
                }
                let unpaidBreakMinutes = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(duration_minutes), 0)
                    FROM break_records
                    WHERE labor_entry_id = ? AND COALESCE(is_paid, 1) = 0 AND deleted_at IS NULL
                    """, arguments: [laborEntryId]) ?? 0
                let totalHours = max(0, rawHours - (unpaidBreakMinutes / 60.0))
                allocation = try Self.allocateOvertimeHours(
                    dbConn: dbConn,
                    userId: userId,
                    laborEntryId: laborEntryId,
                    clockInTimestamp: newClockIn,
                    totalHours: totalHours
                )
                newStatus = "completed"
            } else {
                allocation = (0, 0)
                newStatus = "clocked_in"
            }

            try dbConn.execute(sql: """
                UPDATE labor_entries
                SET clock_in = ?,
                    clock_out = ?,
                    regular_hours = ROUND(?, 2),
                    overtime_hours = ROUND(?, 2),
                    status = ?,
                    edited_by = ?
                WHERE id = ?
                """, arguments: [
                newClockIn, newClockOut, allocation.regular, allocation.overtime,
                newStatus, correctedBy, laborEntryId
            ])

            try dbConn.execute(sql: """
                INSERT INTO labor_entry_correction_audits
                    (labor_entry_id, corrected_by, reason,
                     old_clock_in, new_clock_in, old_clock_out, new_clock_out,
                     old_regular_hours, new_regular_hours,
                     old_overtime_hours, new_overtime_hours,
                     old_status, new_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ROUND(?, 2), ?, ROUND(?, 2), ?, ?)
                """, arguments: [
                laborEntryId, correctedBy, trimmedReason,
                oldClockIn, newClockIn, oldClockOut, newClockOut,
                oldRegularHours, allocation.regular,
                oldOvertimeHours, allocation.overtime,
                oldStatus, newStatus
            ])

            return dbConn.lastInsertedRowID
        }
    }

    public func listLaborEntryCorrectionAudits(laborEntryId: Int64) throws -> [LaborEntryCorrectionAudit] {
        try db.writer.read { dbConn in
            try LaborEntryCorrectionAudit.fetchAll(
                dbConn,
                sql: """
                    SELECT *
                    FROM labor_entry_correction_audits
                    WHERE labor_entry_id = ?
                    ORDER BY created_at DESC, id DESC
                    """,
                arguments: [laborEntryId]
            )
        }
    }

    /// Get the active (clocked-in) labor entry for a user, if any.
    public func getActiveClockEntry(userId: Int64) throws -> LaborEntryRow? {
        do {
            return try db.writer.read { dbConn -> LaborEntryRow? in
                guard let row = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT le.*,
                               COALESCE(u.display_name, u.email, 'Unknown') AS user_name,
                               j.job_name
                        FROM labor_entries le
                        LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                        LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                        WHERE le.user_id = ? AND le.status = 'clocked_in' AND le.deleted_at IS NULL
                        LIMIT 1
                        """,
                    arguments: [userId]
                ) else { return nil }

                return LaborEntryRow(
                    id: row["id"] ?? 0,
                    userId: row["user_id"] ?? 0,
                    userName: row["user_name"] ?? "Unknown",
                    jobId: row["job_id"] ?? 0,
                    jobName: row["job_name"] ?? "",
                    clockIn: row["clock_in"] ?? "",
                    clockOut: row["clock_out"] as String?,
                    status: row["status"] ?? "clocked_in",
                    regularHours: row["regular_hours"] ?? 0.0,
                    overtimeHours: row["overtime_hours"] ?? 0.0,
                    gpsInLat: row["clock_in_gps_lat"] as Double?,
                    gpsInLng: row["clock_in_gps_lng"] as Double?,
                    gpsOutLat: row["clock_out_gps_lat"] as Double?,
                    gpsOutLng: row["clock_out_gps_lng"] as Double?,
                    linkedTodoId: row["linked_todo_id"] as Int64?,
                    workType: row["work_type"] as String?
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// List labor entries, optionally filtered by job and/or user.
    public func listLaborEntries(
        jobId: Int64? = nil,
        userId: Int64? = nil,
        limit: Int = 100
    ) throws -> [LaborEntryRow] {
        do {
            return try db.writer.read { dbConn -> [LaborEntryRow] in
                var whereClauses = ["le.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let jobId {
                    whereClauses.append("le.job_id = ?")
                    args.append(jobId)
                }
                if let userId {
                    whereClauses.append("le.user_id = ?")
                    args.append(userId)
                }

                args.append(limit)

                let sql = """
                    SELECT le.*,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name,
                           j.job_name
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY le.clock_in DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    LaborEntryRow(
                        id: row["id"] ?? 0,
                        userId: row["user_id"] ?? 0,
                        userName: row["user_name"] ?? "Unknown",
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        clockIn: row["clock_in"] ?? "",
                        clockOut: row["clock_out"] as String?,
                        status: row["status"] ?? "clocked_in",
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0,
                        gpsInLat: row["clock_in_gps_lat"] as Double?,
                        gpsInLng: row["clock_in_gps_lng"] as Double?,
                        gpsOutLat: row["clock_out_gps_lat"] as Double?,
                        gpsOutLng: row["clock_out_gps_lng"] as Double?,
                        linkedTodoId: row["linked_todo_id"] as Int64?,
                        workType: row["work_type"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Clock + To-Do Integration

    /// A lightweight to-do item for the clock page picker.
    public struct ClockTodoItem: Sendable, Identifiable {
        public let id: Int64
        public let title: String
        public let content: String?
        public let taskStatus: String?

        public init(id: Int64, title: String, content: String?, taskStatus: String?) {
            self.id = id
            self.title = title
            self.content = content
            self.taskStatus = taskStatus
        }
    }

    /// Get active (incomplete) to-dos for a job from its notebooks.
    public func getActiveJobTodos(jobId: Int64) throws -> [ClockTodoItem] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT ne.id, ne.title, ne.content, ne.task_status
                    FROM notebook_entries ne
                    JOIN notebook_sections ns ON ns.id = ne.section_id
                    JOIN notebooks n ON n.id = ns.notebook_id
                    WHERE n.job_id = ?
                      AND ne.entry_type = 'todo'
                      AND COALESCE(ne.task_status, 'pending') != 'complete'
                      AND ne.deleted_at IS NULL
                      AND ne.is_deleted = 0
                      AND ns.deleted_at IS NULL
                      AND n.deleted_at IS NULL
                    ORDER BY ne.sort_order ASC
                    """, arguments: [jobId])
                return rows.map { row in
                    ClockTodoItem(
                        id: row["id"] ?? 0,
                        title: row["title"] ?? "",
                        content: row["content"] as String?,
                        taskStatus: row["task_status"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// A summary of todo completion for a job.
    public struct JobTodoSummary: Sendable {
        public let totalTodos: Int
        public let completedTodos: Int

        public init(totalTodos: Int, completedTodos: Int) {
            self.totalTodos = totalTodos
            self.completedTodos = completedTodos
        }
    }

    /// Get a summary of todo progress for a job (total and completed counts).
    public func getJobTodoSummary(jobId: Int64) throws -> JobTodoSummary {
        do {
            return try db.writer.read { dbConn in
                let row = try Row.fetchOne(dbConn, sql: """
                    SELECT
                        COUNT(*) AS total,
                        SUM(CASE WHEN COALESCE(ne.task_status, 'pending') = 'complete' THEN 1 ELSE 0 END) AS completed
                    FROM notebook_entries ne
                    JOIN notebook_sections ns ON ns.id = ne.section_id
                    JOIN notebooks n ON n.id = ns.notebook_id
                    WHERE n.job_id = ?
                      AND ne.entry_type = 'todo'
                      AND ne.deleted_at IS NULL
                      AND ne.is_deleted = 0
                      AND ns.deleted_at IS NULL
                      AND n.deleted_at IS NULL
                    """, arguments: [jobId])
                return JobTodoSummary(
                    totalTodos: row?["total"] ?? 0,
                    completedTodos: row?["completed"] ?? 0
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return JobTodoSummary(totalTodos: 0, completedTodos: 0)
            }
            throw error
        }
    }

    /// Link a clock entry to a specific to-do.
    public func linkClockEntryToTodo(clockEntryId: Int64, todoId: Int64?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE labor_entries SET linked_todo_id = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [todoId, clockEntryId]
            )
        }
    }

    /// Set work type for a clock entry ("new_work" or "warranty").
    public func setClockEntryWorkType(clockEntryId: Int64, workType: String) throws {
        guard !workType.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw JobsError.requiredFieldEmpty
        }
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE labor_entries SET work_type = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [workType, clockEntryId]
            )
        }
    }

    // MARK: - Today's Clock Entries (Grouped)

    /// Summary of a clock entry for today's hours breakdown.
    public struct ClockEntrySummary: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String
        public let todoName: String?
        public let startTime: Date
        public let endTime: Date?  // nil = still clocked in
        public let workType: String

        public var duration: TimeInterval {
            (endTime ?? Date()).timeIntervalSince(startTime)
        }
    }

    /// Group of clock entries for a single job (used in today's breakdown).
    public struct JobClockGroup: Sendable, Identifiable {
        public let jobId: Int64
        public let jobName: String
        public let entries: [ClockEntrySummary]
        public var id: Int64 { jobId }

        public var totalDuration: TimeInterval {
            entries.reduce(0) { $0 + $1.duration }
        }
    }

    /// Get today's clock entries for a user, grouped by job with optional to-do names.
    public func getTodaysClockEntries(userId: Int64) throws -> [JobClockGroup] {
        do { return try db.writer.read { dbConn -> [JobClockGroup] in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT le.id, le.job_id, j.job_name, le.clock_in, le.clock_out,
                       le.linked_todo_id, le.work_type,
                       ne.title AS todo_name
                FROM labor_entries le
                LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                LEFT JOIN notebook_entries ne ON ne.id = le.linked_todo_id AND ne.deleted_at IS NULL
                WHERE le.user_id = ?
                  AND \(Self.localDateSQL("le.clock_in")) = date('now', 'localtime')
                  AND le.deleted_at IS NULL
                ORDER BY le.clock_in ASC
                """, arguments: [userId])

            var groupMap: [Int64: [ClockEntrySummary]] = [:]
            var groupOrder: [Int64] = []
            var jobNames: [Int64: String] = [:]

            for row in rows {
                let entryId: Int64 = row["id"] ?? 0
                let jobId: Int64 = row["job_id"] ?? 0
                let jobName: String = row["job_name"] ?? "Unknown"
                let clockInStr: String = row["clock_in"] ?? ""
                let clockOutStr: String? = row["clock_out"] as String?
                let todoName: String? = row["todo_name"] as String?
                let wType: String = row["work_type"] ?? "new_work"

                let startDate = Self.parseSQLiteUTCDateTime(clockInStr) ?? Date()
                let endDate: Date? = clockOutStr.flatMap { Self.parseSQLiteUTCDateTime($0) }

                let summary = ClockEntrySummary(
                    id: entryId,
                    jobId: jobId,
                    jobName: jobName,
                    todoName: todoName,
                    startTime: startDate,
                    endTime: endDate,
                    workType: wType
                )

                if groupMap[jobId] == nil {
                    groupOrder.append(jobId)
                    jobNames[jobId] = jobName
                }
                groupMap[jobId, default: []].append(summary)
            }

            return groupOrder.compactMap { jobId in
                guard let entries = groupMap[jobId] else { return nil }
                return JobClockGroup(
                    jobId: jobId,
                    jobName: jobNames[jobId] ?? "Unknown",
                    entries: entries
                )
            }
        } } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a labor summary for a specific job.
    public func getLaborSummary(jobId: Int64) throws -> LaborSummary {
        do {
            return try db.writer.read { dbConn -> LaborSummary in
                let row = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT COUNT(*) AS total_entries,
                               COALESCE(SUM(regular_hours), 0) AS total_regular,
                               COALESCE(SUM(overtime_hours), 0) AS total_overtime,
                               COUNT(DISTINCT user_id) AS unique_workers
                        FROM labor_entries
                        WHERE job_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [jobId]
                )

                return LaborSummary(
                    totalEntries: row?["total_entries"] ?? 0,
                    totalRegularHours: row?["total_regular"] ?? 0.0,
                    totalOvertimeHours: row?["total_overtime"] ?? 0.0,
                    uniqueWorkers: row?["unique_workers"] ?? 0
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return LaborSummary(totalEntries: 0, totalRegularHours: 0, totalOvertimeHours: 0, uniqueWorkers: 0)
            }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3. Clock-Out Questionnaire
    // =========================================================================

    /// Get all active clock-out questions sorted by sort_order.
    public func getActiveQuestions() throws -> [QuestionnaireItem] {
        do {
            return try db.writer.read { dbConn -> [QuestionnaireItem] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT id, question_text, answer_type, is_required
                        FROM clock_out_questions
                        WHERE is_active = 1
                        ORDER BY sort_order ASC
                        """
                )
                return rows.map { row in
                    QuestionnaireItem(
                        questionId: row["id"] ?? 0,
                        questionText: row["question_text"] ?? "",
                        answerType: row["answer_type"] ?? "text",
                        isRequired: (row["is_required"] as Int?) == 1,
                        answer: nil
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Save clock-out responses for a labor entry.
    ///
    /// - Parameter responses: Array of tuples (questionId, answerText).
    public func saveClockOutResponses(
        laborEntryId: Int64,
        responses: [(questionId: Int64, answer: String)]
    ) throws {
        try db.writer.write { dbConn in
            let requiredIds = try Row.fetchAll(
                dbConn,
                sql: "SELECT id FROM clock_out_questions WHERE is_required = 1 AND is_active = 1"
            ).map { (row: Row) -> Int64 in row["id"] as Int64 }
            let answeredSet = Set(
                responses
                    .filter { !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { $0.questionId }
            )
            for reqId in requiredIds {
                guard answeredSet.contains(reqId) else {
                    throw JobsError.requiredQuestionNotAnswered(reqId)
                }
            }
            for response in responses {
                try dbConn.execute(
                    sql: """
                        INSERT INTO clock_out_responses
                        (labor_entry_id, question_id, answer_text, answered_at)
                        VALUES (?, ?, ?, datetime('now'))
                        """,
                    arguments: [laborEntryId, response.questionId, response.answer]
                )
            }
        }
    }

    /// Get responses for a specific labor entry with question text.
    public func getResponsesForEntry(laborEntryId: Int64) throws -> [QuestionnaireItem] {
        do {
            return try db.writer.read { dbConn -> [QuestionnaireItem] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT coq.id AS question_id, coq.question_text, coq.answer_type, coq.is_required,
                               cor.answer_text
                        FROM clock_out_responses cor
                        JOIN clock_out_questions coq ON coq.id = cor.question_id
                        WHERE cor.labor_entry_id = ? AND cor.deleted_at IS NULL
                        ORDER BY coq.sort_order ASC
                        """,
                    arguments: [laborEntryId]
                )
                return rows.map { row in
                    QuestionnaireItem(
                        questionId: row["question_id"] ?? 0,
                        questionText: row["question_text"] ?? "",
                        answerType: row["answer_type"] ?? "text",
                        isRequired: (row["is_required"] as Int?) == 1,
                        answer: row["answer_text"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 4. One-Time Questions
    // =========================================================================

    /// Get one-time questions for a specific job.
    public func getQuestionsForJob(jobId: Int64) throws -> [OneTimeQuestionRow] {
        do {
            return try db.writer.read { dbConn -> [OneTimeQuestionRow] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT otq.*,
                               j.job_name,
                               COALESCE(uc.display_name, uc.email, 'Unknown') AS created_by_name,
                               COALESCE(ua.display_name, ua.email) AS answered_by_name
                        FROM one_time_questions otq
                        LEFT JOIN jobs j ON j.id = otq.job_id AND j.deleted_at IS NULL
                        LEFT JOIN users uc ON uc.id = otq.created_by AND uc.deleted_at IS NULL
                        LEFT JOIN users ua ON ua.id = otq.answered_by AND ua.deleted_at IS NULL
                        WHERE otq.job_id = ? AND otq.deleted_at IS NULL
                        ORDER BY otq.created_at DESC
                        """,
                    arguments: [jobId]
                )
                return rows.map { row in
                    OneTimeQuestionRow(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        questionText: row["question_text"] ?? "",
                        status: row["status"] ?? "pending",
                        createdByName: row["created_by_name"] ?? "Unknown",
                        answerText: row["answer_text"] as String?,
                        answeredByName: row["answered_by_name"] as String?,
                        answeredAt: row["answered_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new one-time question for a job.
    ///
    /// - Returns: The new question row ID.
    @discardableResult
    public func createOneTimeQuestion(
        jobId: Int64,
        text: String,
        createdBy: Int64,
        targetUserId: Int64? = nil
    ) throws -> Int64 {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw JobsError.requiredFieldEmpty }
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO one_time_questions
                    (job_id, target_user_id, question_text, created_by, created_at)
                    VALUES (?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [jobId, targetUserId, text, createdBy]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Answer a one-time question.
    public func answerOneTimeQuestion(
        questionId: Int64,
        answerText: String,
        answeredBy: Int64
    ) throws {
        guard !answerText.trimmingCharacters(in: .whitespaces).isEmpty else { throw JobsError.requiredFieldEmpty }
        try db.writer.write { dbConn in
            let count = try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM one_time_questions WHERE id = ? AND deleted_at IS NULL",
                arguments: [questionId]
            ) ?? 0

            guard count > 0 else {
                throw JobsError.questionNotFound(questionId)
            }

            try dbConn.execute(
                sql: """
                    UPDATE one_time_questions
                    SET answer_text = ?, answered_by = ?, status = 'answered', answered_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [answerText, answeredBy, questionId]
            )
        }
    }

    /// Get pending one-time questions, optionally filtered by target user.
    public func getPendingQuestions(userId: Int64? = nil) throws -> [OneTimeQuestionRow] {
        do {
            return try db.writer.read { dbConn -> [OneTimeQuestionRow] in
                var whereClauses = ["otq.status = 'pending'", "otq.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let userId {
                    whereClauses.append("(otq.target_user_id = ? OR otq.target_user_id IS NULL)")
                    args.append(userId)
                }

                let sql = """
                    SELECT otq.*,
                           j.job_name,
                           COALESCE(uc.display_name, uc.email, 'Unknown') AS created_by_name,
                           COALESCE(ua.display_name, ua.email) AS answered_by_name
                    FROM one_time_questions otq
                    LEFT JOIN jobs j ON j.id = otq.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users uc ON uc.id = otq.created_by AND uc.deleted_at IS NULL
                    LEFT JOIN users ua ON ua.id = otq.answered_by AND ua.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY otq.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    OneTimeQuestionRow(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        questionText: row["question_text"] ?? "",
                        status: row["status"] ?? "pending",
                        createdByName: row["created_by_name"] ?? "Unknown",
                        answerText: row["answer_text"] as String?,
                        answeredByName: row["answered_by_name"] as String?,
                        answeredAt: row["answered_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5. Daily Reports
    // =========================================================================

    /// Save the clock-out Daily Report answer into the job's Daily Report notebook.
    ///
    /// Blank answers are ignored so optional/accidental whitespace does not create empty reports.
    /// The notebook is scoped to the labor entry's job and worker so reports remain tied to the
    /// job that was just clocked out.
    @discardableResult
    public func saveClockOutDailyReport(laborEntryId: Int64, dailyReport: String) throws -> Int64? {
        let trimmedReport = dailyReport.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReport.isEmpty else { return nil }

        return try db.writer.write { dbConn in
            guard let labor = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT le.job_id, le.user_id, le.clock_in,
                           COALESCE(j.job_name, j.job_number, 'Shop / Warehouse') AS job_name
                    FROM labor_entries le
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    WHERE le.id = ? AND le.deleted_at IS NULL
                    """,
                arguments: [laborEntryId]
            ) else {
                throw JobsError.laborEntryNotFound(laborEntryId)
            }

            let jobId: Int64 = labor["job_id"] ?? 0
            let userId: Int64 = labor["user_id"] ?? 0
            let jobName: String = labor["job_name"] ?? "Shop / Warehouse"
            let clockIn: String = labor["clock_in"] ?? ""
            let clockDate = String(clockIn.prefix(10))
            let reportDate = clockDate.isEmpty ? Self.localDateString() : clockDate

            var notebookId = try Int64.fetchOne(
                dbConn,
                sql: """
                    SELECT id FROM notebooks
                    WHERE notebook_type = 'daily-report'
                      AND job_id = ?
                      AND created_by = ?
                      AND deleted_at IS NULL
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                arguments: [jobId, userId]
            )

            if notebookId == nil {
                try dbConn.execute(
                    sql: """
                        INSERT INTO notebooks
                            (title, description, job_id, created_by, notebook_type, status, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 'daily-report', 'active', datetime('now'), datetime('now'))
                        """,
                    arguments: ["Daily Reports — \(jobName)", "Clock-out daily reports captured from the end-of-day questionnaire.", jobId, userId]
                )
                notebookId = dbConn.lastInsertedRowID
            }

            guard let nbId = notebookId else { return nil }

            var sectionId = try Int64.fetchOne(
                dbConn,
                sql: """
                    SELECT id FROM notebook_sections
                    WHERE notebook_id = ? AND name = 'Reports' AND deleted_at IS NULL
                    ORDER BY sort_order ASC, id ASC
                    LIMIT 1
                    """,
                arguments: [nbId]
            )

            if sectionId == nil {
                try dbConn.execute(
                    sql: """
                        INSERT INTO notebook_sections (notebook_id, name, section_type, sort_order, created_at)
                        VALUES (?, 'Reports', 'notes', 0, datetime('now'))
                        """,
                    arguments: [nbId]
                )
                sectionId = dbConn.lastInsertedRowID
            }

            guard let secId = sectionId else { return nil }

            let content = """
                ## Daily Report — \(reportDate)

                ### Job
                \(jobName)

                ### Clock-Out Daily Report
                \(trimmedReport)

                _Captured at clock-out from labor entry #\(laborEntryId)._
                """

            try dbConn.execute(
                sql: """
                    INSERT INTO notebook_entries
                        (section_id, title, content, entry_type, created_by, updated_by, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, 'daily-report', ?, ?, 0, datetime('now'), datetime('now'))
                    """,
                arguments: [secId, "Daily Report — \(reportDate)", content, userId, userId]
            )
            let entryId = dbConn.lastInsertedRowID

            try dbConn.execute(
                sql: "UPDATE notebooks SET updated_at = datetime('now') WHERE id = ?",
                arguments: [nbId]
            )

            return entryId
        }
    }

    private static func localDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// List daily reports, optionally filtered by job.
    public func listReports(jobId: Int64? = nil, limit: Int = 50) throws -> [DailyReportRow] {
        do {
            return try db.writer.read { dbConn -> [DailyReportRow] in
                var whereClauses = ["dr.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let jobId {
                    whereClauses.append("dr.job_id = ?")
                    args.append(jobId)
                }

                args.append(limit)

                let sql = """
                    SELECT dr.id, dr.job_id, dr.report_date, dr.status,
                           j.job_name,
                           COALESCE(u.display_name, u.email) AS reviewed_by_name
                    FROM daily_reports dr
                    LEFT JOIN jobs j ON j.id = dr.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = dr.reviewed_by AND u.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY dr.report_date DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    DailyReportRow(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        reportDate: row["report_date"] ?? "",
                        status: row["status"] ?? "generated",
                        reviewedByName: row["reviewed_by_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single daily report by ID.
    public func getReport(id: Int64) throws -> DailyReportRow? {
        do {
            return try db.writer.read { dbConn -> DailyReportRow? in
                guard let row = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT dr.id, dr.job_id, dr.report_date, dr.status,
                               j.job_name,
                               COALESCE(u.display_name, u.email) AS reviewed_by_name
                        FROM daily_reports dr
                        LEFT JOIN jobs j ON j.id = dr.job_id AND j.deleted_at IS NULL
                        LEFT JOIN users u ON u.id = dr.reviewed_by AND u.deleted_at IS NULL
                        WHERE dr.id = ? AND dr.deleted_at IS NULL
                        """,
                    arguments: [id]
                ) else { return nil }

                return DailyReportRow(
                    id: row["id"] ?? 0,
                    jobId: row["job_id"] ?? 0,
                    jobName: row["job_name"] ?? "",
                    reportDate: row["report_date"] ?? "",
                    status: row["status"] ?? "generated",
                    reviewedByName: row["reviewed_by_name"] as String?
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Generate (or replace) a daily report for a job and date.
    /// Uses INSERT OR REPLACE to upsert on the (job_id, report_date) unique constraint.
    ///
    /// - Returns: The report row ID.
    @discardableResult
    public func generateDailyReport(
        jobId: Int64,
        reportDate: String,
        reportJson: String,
        generatedBy: Int64
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR REPLACE INTO daily_reports
                    (job_id, report_date, report_json, status, generated_at)
                    VALUES (?, ?, ?, 'generated', datetime('now'))
                    """,
                arguments: [jobId, reportDate, reportJson]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Mark a daily report as reviewed.
    public func markReportReviewed(reportId: Int64, reviewedBy: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE daily_reports
                    SET status = 'reviewed', reviewed_by = ?, reviewed_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [reviewedBy, reportId]
            )
        }
    }

    // =========================================================================
    // MARK: - 6. Team Members
    // =========================================================================

    /// Get all team members for a job with user names.
    public func getTeamMembers(jobId: Int64) throws -> [TeamMemberRow] {
        do {
            return try db.writer.read { dbConn -> [TeamMemberRow] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT jtm.id, jtm.user_id, jtm.role, jtm.assigned_at,
                               COALESCE(u.display_name, u.email, 'Unknown') AS user_name
                        FROM job_team_members jtm
                        LEFT JOIN users u ON u.id = jtm.user_id AND u.deleted_at IS NULL
                        WHERE jtm.job_id = ? AND jtm.deleted_at IS NULL
                        ORDER BY jtm.assigned_at ASC
                        """,
                    arguments: [jobId]
                )
                return rows.map { row in
                    TeamMemberRow(
                        id: row["id"] ?? 0,
                        userId: row["user_id"] ?? 0,
                        userName: row["user_name"] ?? "Unknown",
                        role: row["role"] ?? "member",
                        joinedAt: row["assigned_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Add a team member to a job.
    ///
    /// - Returns: The new team member row ID.
    @discardableResult
    public func addTeamMember(
        jobId: Int64,
        userId: Int64,
        role: String = "member"
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            let jobExists = try Int.fetchOne(dbConn,
                sql: "SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL",
                arguments: [jobId]) ?? 0
            guard jobExists > 0 else { throw JobsError.jobNotFound(jobId) }
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO job_team_members
                    (job_id, user_id, role, assigned_at)
                    VALUES (?, ?, ?, datetime('now'))
                    """,
                arguments: [jobId, userId, role]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Remove a team member (soft-delete).
    public func removeTeamMember(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE job_team_members SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - 7. Job Parts
    // =========================================================================

    /// Get all parts consumed on a job with part name/code.
    public func getJobParts(jobId: Int64) throws -> [JobPartRow] {
        do {
            return try db.writer.read { dbConn -> [JobPartRow] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT jp.id, jp.part_id, jp.qty_consumed, jp.qty_returned,
                               jp.unit_cost_at_consume, jp.unit_sell_at_consume,
                               p.name AS part_name, p.code AS part_code
                        FROM job_parts jp
                        LEFT JOIN parts p ON p.id = jp.part_id AND p.deleted_at IS NULL
                        WHERE jp.job_id = ? AND jp.deleted_at IS NULL
                        ORDER BY jp.consumed_at DESC
                        """,
                    arguments: [jobId]
                )
                return rows.map { row in
                    JobPartRow(
                        id: row["id"] ?? 0,
                        partId: row["part_id"] ?? 0,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        qtyConsumed: row["qty_consumed"] ?? 0,
                        qtyReturned: row["qty_returned"] ?? 0,
                        unitCost: row["unit_cost_at_consume"] as Double?,
                        unitSell: row["unit_sell_at_consume"] as Double?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Add a part consumption record to a job.
    ///
    /// - Returns: The new job_parts row ID.
    @discardableResult
    public func addJobPart(
        jobId: Int64,
        partId: Int64,
        qty: Int,
        costAtConsume: Double? = nil,
        performedBy: Int64
    ) throws -> Int64 {
        guard qty > 0 else { throw JobsError.invalidReturnQuantity(partId) }
        return try db.writer.write { dbConn in
            let partExists = try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM parts WHERE id = ? AND deleted_at IS NULL",
                arguments: [partId]
            ) ?? 0
            guard partExists > 0 else { throw JobsError.partNotFound(partId) }
            try dbConn.execute(
                sql: """
                    INSERT INTO job_parts
                    (job_id, part_id, qty_consumed, unit_cost_at_consume, consumed_by, consumed_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [jobId, partId, qty, costAtConsume, performedBy]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Record a return of parts from a job.
    public func returnJobPart(jobPartId: Int64, returnQty: Int) throws {
        guard returnQty > 0 else { throw JobsError.invalidReturnQuantity(jobPartId) }
        try db.writer.write { dbConn in
            guard let row = try Row.fetchOne(
                dbConn,
                sql: "SELECT qty_consumed, qty_returned FROM job_parts WHERE id = ? AND deleted_at IS NULL",
                arguments: [jobPartId]
            ) else { throw JobsError.laborEntryNotFound(jobPartId) }
            let consumed: Int = row["qty_consumed"] ?? 0
            let alreadyReturned: Int = row["qty_returned"] ?? 0
            guard alreadyReturned + returnQty <= consumed else {
                throw JobsError.invalidReturnQuantity(jobPartId)
            }
            try dbConn.execute(
                sql: """
                    UPDATE job_parts
                    SET qty_returned = qty_returned + ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [returnQty, jobPartId]
            )
        }
    }

    /// List material staged in the job's `pulled` stock bucket and ready for field use.
    public func listReadyJobMaterials(jobId: Int64) throws -> [JobReadyMaterialRow] {
        do {
            return try db.writer.read { dbConn in
                try Self.requireActiveJob(jobId, dbConn: dbConn)
                // CTE resolves the latest staged-pull movement per part in one pass,
                // avoiding two correlated subqueries per stock row.
                let rows = try Row.fetchAll(dbConn, sql: """
                    WITH latest_move AS (
                        SELECT sm.part_id, sm.movement_type, sm.created_at
                        FROM stock_movements sm
                        INNER JOIN (
                            SELECT part_id, MAX(id) AS max_id
                            FROM stock_movements
                            WHERE to_location_type = 'pulled'
                              AND to_location_id = ?
                              AND job_id = ?
                              AND deleted_at IS NULL
                            GROUP BY part_id
                        ) lm ON sm.id = lm.max_id AND sm.part_id = lm.part_id
                    )
                    SELECT s.part_id,
                           s.qty AS staged_qty,
                           p.name AS part_name,
                           p.code AS part_code,
                           lm.movement_type AS source_movement_type,
                           lm.created_at AS last_moved_at
                    FROM stock s
                    LEFT JOIN parts p ON p.id = s.part_id AND p.deleted_at IS NULL
                    LEFT JOIN latest_move lm ON lm.part_id = s.part_id
                    WHERE s.location_type = 'pulled'
                      AND s.location_id = ?
                      AND s.qty > 0
                      AND s.deleted_at IS NULL
                    ORDER BY p.name, s.part_id
                    """, arguments: [jobId, jobId, jobId])
                return rows.map { row in
                    let sourceType = (row["source_movement_type"] as String?) ?? StockMovement.MovementType.receivingStaged.rawValue
                    return JobReadyMaterialRow(
                        id: row["part_id"] ?? 0,
                        partId: row["part_id"] ?? 0,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        stagedQty: row["staged_qty"] ?? 0,
                        sourceSummary: StockMovement.MovementType.displayName(forRawValue: sourceType),
                        lastMovedAt: row["last_moved_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Pull available inventory from a warehouse/truck/shop bucket into job-ready staged stock.
    @discardableResult
    public func pullJobMaterial(
        jobId: Int64,
        partId: Int64,
        qty: Int,
        fromLocationType: String,
        fromLocationId: Int64,
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        guard qty > 0 else { throw JobsError.invalidReturnQuantity(partId) }
        return try db.writer.write { dbConn in
            try Self.requireActiveJob(jobId, dbConn: dbConn)
            try Self.requireActivePart(partId, dbConn: dbConn)
            try Self.requireActiveUser(performedBy, dbConn: dbConn)

            let available = try Self.stockQty(partId: partId, locationType: fromLocationType, locationId: fromLocationId, dbConn: dbConn)
            guard available >= qty else {
                throw JobsError.insufficientStagedMaterial(available: available, requested: qty)
            }

            let movementId = try Self.insertStockMovement(
                partId: partId,
                qty: qty,
                fromLocationType: fromLocationType,
                fromLocationId: fromLocationId,
                toLocationType: "pulled",
                toLocationId: jobId,
                movementType: StockMovement.MovementType.transfer.rawValue,
                reason: "Pulled for job",
                notes: notes,
                performedBy: performedBy,
                jobId: jobId,
                unitCostAtMove: nil,
                dbConn: dbConn
            )
            try Self.decrementStock(partId: partId, locationType: fromLocationType, locationId: fromLocationId, qty: qty, dbConn: dbConn)
            try Self.incrementStock(partId: partId, locationType: "pulled", locationId: jobId, qty: qty, dbConn: dbConn)
            return movementId
        }
    }

    /// Consume staged material into `job_parts` and decrement the job's pulled stock atomically.
    @discardableResult
    public func consumeStagedJobMaterial(
        jobId: Int64,
        partId: Int64,
        qty: Int,
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        guard qty > 0 else { throw JobsError.invalidReturnQuantity(partId) }
        return try db.writer.write { dbConn in
            try Self.requireActiveJob(jobId, dbConn: dbConn)
            try Self.requireActivePart(partId, dbConn: dbConn)
            try Self.requireActiveUser(performedBy, dbConn: dbConn)

            let available = try Self.stockQty(partId: partId, locationType: "pulled", locationId: jobId, dbConn: dbConn)
            guard available >= qty else {
                throw JobsError.insufficientStagedMaterial(available: available, requested: qty)
            }

            let unitCost = try Self.latestStagedUnitCost(partId: partId, jobId: jobId, dbConn: dbConn)

            try dbConn.execute(sql: """
                INSERT INTO job_parts
                    (job_id, part_id, qty_consumed, unit_cost_at_consume, consumed_by, consumed_at, notes)
                VALUES (?, ?, ?, ?, ?, datetime('now'), ?)
                """, arguments: [jobId, partId, qty, unitCost, performedBy, notes])
            let jobPartId = dbConn.lastInsertedRowID

            try Self.insertStockMovement(
                partId: partId,
                qty: qty,
                fromLocationType: "pulled",
                fromLocationId: jobId,
                toLocationType: nil,
                toLocationId: nil,
                movementType: StockMovement.MovementType.jobPull.rawValue,
                reason: "Consumed on job",
                notes: notes,
                performedBy: performedBy,
                jobId: jobId,
                unitCostAtMove: unitCost,
                dbConn: dbConn
            )
            try Self.decrementStock(partId: partId, locationType: "pulled", locationId: jobId, qty: qty, dbConn: dbConn)

            return jobPartId
        }
    }

    /// Return unused staged material from a job into warehouse holding/review.
    @discardableResult
    public func returnStagedJobMaterial(
        jobId: Int64,
        partId: Int64,
        qty: Int,
        condition: String = "usable",
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        guard qty > 0 else { throw JobsError.invalidReturnQuantity(partId) }
        return try db.writer.write { dbConn in
            try Self.requireActiveJob(jobId, dbConn: dbConn)
            try Self.requireActivePart(partId, dbConn: dbConn)
            try Self.requireActiveUser(performedBy, dbConn: dbConn)

            let available = try Self.stockQty(partId: partId, locationType: "pulled", locationId: jobId, dbConn: dbConn)
            guard available >= qty else {
                throw JobsError.insufficientStagedMaterial(available: available, requested: qty)
            }

            let stagedUnitCost = try Self.latestStagedUnitCost(partId: partId, jobId: jobId, dbConn: dbConn)
            try Self.insertStockMovement(
                partId: partId,
                qty: qty,
                fromLocationType: "pulled",
                fromLocationId: jobId,
                toLocationType: nil,
                toLocationId: nil,
                movementType: StockMovement.MovementType.stockReturn.rawValue,
                reason: "Returned unused job material",
                notes: notes,
                performedBy: performedBy,
                jobId: jobId,
                unitCostAtMove: stagedUnitCost,
                dbConn: dbConn
            )
            try Self.decrementStock(partId: partId, locationType: "pulled", locationId: jobId, qty: qty, dbConn: dbConn)

            return try Self.insertJobReturnIntake(
                sourceJobId: jobId,
                returnSource: "job",
                returnedBy: performedBy,
                partId: partId,
                qty: qty,
                condition: condition,
                sourceJobPartId: nil,
                notes: notes,
                dbConn: dbConn
            )
        }
    }

    /// Return unused pulled material directly back to truck/warehouse inventory.
    @discardableResult
    public func returnPulledJobMaterial(
        jobId: Int64,
        partId: Int64,
        qty: Int,
        toLocationType: String,
        toLocationId: Int64,
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        guard qty > 0 else { throw JobsError.invalidReturnQuantity(partId) }
        return try db.writer.write { dbConn in
            try Self.requireActiveJob(jobId, dbConn: dbConn)
            try Self.requireActivePart(partId, dbConn: dbConn)
            try Self.requireActiveUser(performedBy, dbConn: dbConn)

            let available = try Self.stockQty(partId: partId, locationType: "pulled", locationId: jobId, dbConn: dbConn)
            guard available >= qty else {
                throw JobsError.insufficientStagedMaterial(available: available, requested: qty)
            }

            let stagedUnitCost = try Self.latestStagedUnitCost(partId: partId, jobId: jobId, dbConn: dbConn)
            let movementId = try Self.insertStockMovement(
                partId: partId,
                qty: qty,
                fromLocationType: "pulled",
                fromLocationId: jobId,
                toLocationType: toLocationType,
                toLocationId: toLocationId,
                movementType: StockMovement.MovementType.stockReturn.rawValue,
                reason: "Returned unused job material to inventory",
                notes: notes,
                performedBy: performedBy,
                jobId: jobId,
                unitCostAtMove: stagedUnitCost,
                dbConn: dbConn
            )
            try Self.decrementStock(partId: partId, locationType: "pulled", locationId: jobId, qty: qty, dbConn: dbConn)
            try Self.incrementStock(partId: partId, locationType: toLocationType, locationId: toLocationId, qty: qty, dbConn: dbConn)
            return movementId
        }
    }

    /// Reverse consumed material and create a warehouse return-intake item in one transaction.
    @discardableResult
    public func returnConsumedJobMaterial(
        jobPartId: Int64,
        returnQty: Int,
        condition: String = "usable",
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        guard returnQty > 0 else { throw JobsError.invalidReturnQuantity(jobPartId) }
        return try db.writer.write { dbConn in
            try Self.requireActiveUser(performedBy, dbConn: dbConn)
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT job_id, part_id, qty_consumed, qty_returned, unit_cost_at_consume
                FROM job_parts
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobPartId]) else {
                throw JobsError.laborEntryNotFound(jobPartId)
            }

            let jobId: Int64 = row["job_id"] ?? 0
            let partId: Int64 = row["part_id"] ?? 0
            let consumed: Int = row["qty_consumed"] ?? 0
            let alreadyReturned: Int = row["qty_returned"] ?? 0
            guard alreadyReturned + returnQty <= consumed else {
                throw JobsError.invalidReturnQuantity(jobPartId)
            }

            try dbConn.execute(sql: """
                UPDATE job_parts
                SET qty_returned = qty_returned + ?
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [returnQty, jobPartId])

            try Self.insertStockMovement(
                partId: partId,
                qty: returnQty,
                fromLocationType: nil,
                fromLocationId: nil,
                toLocationType: nil,
                toLocationId: nil,
                movementType: StockMovement.MovementType.stockReturn.rawValue,
                reason: "Returned consumed job material",
                notes: notes,
                performedBy: performedBy,
                jobId: jobId,
                unitCostAtMove: row["unit_cost_at_consume"] as Double?,
                dbConn: dbConn
            )

            return try Self.insertJobReturnIntake(
                sourceJobId: jobId,
                returnSource: "job",
                returnedBy: performedBy,
                partId: partId,
                qty: returnQty,
                condition: condition,
                sourceJobPartId: jobPartId,
                notes: notes,
                dbConn: dbConn
            )
        }
    }

    /// Correct a consumed job-part quantity with required audit detail.
    public func correctConsumedJobMaterial(
        jobPartId: Int64,
        adjustedQty: Int,
        performedBy: Int64,
        note: String
    ) throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { throw JobsError.requiredFieldEmpty }
        guard adjustedQty > 0 else { throw JobsError.invalidReturnQuantity(jobPartId) }

        try db.writer.write { dbConn in
            try Self.requireActiveUser(performedBy, dbConn: dbConn)
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT job_id, part_id, qty_consumed, qty_returned, unit_cost_at_consume
                FROM job_parts
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobPartId]) else {
                throw JobsError.laborEntryNotFound(jobPartId)
            }

            let jobId: Int64 = row["job_id"] ?? 0
            let partId: Int64 = row["part_id"] ?? 0
            let originalQty: Int = row["qty_consumed"] ?? 0
            let returnedQty: Int = row["qty_returned"] ?? 0
            guard adjustedQty >= returnedQty else {
                throw JobsError.invalidReturnQuantity(jobPartId)
            }

            try dbConn.execute(sql: """
                UPDATE job_parts
                SET qty_consumed = ?
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [adjustedQty, jobPartId])

            let auditNote = "Correction: original_qty=\(originalQty), adjusted_qty=\(adjustedQty). \(trimmedNote)"
            try Self.insertStockMovement(
                partId: partId,
                qty: abs(adjustedQty - originalQty),
                fromLocationType: nil,
                fromLocationId: nil,
                toLocationType: nil,
                toLocationId: nil,
                movementType: StockMovement.MovementType.adjustment.rawValue,
                reason: "Corrected consumed job material",
                notes: auditNote,
                performedBy: performedBy,
                jobId: jobId,
                unitCostAtMove: row["unit_cost_at_consume"] as Double?,
                dbConn: dbConn
            )
        }
    }

    public func getJobMaterialTotals(jobId: Int64) throws -> JobMaterialTotals {
        do {
            return try db.writer.read { dbConn in
                try Self.requireActiveJob(jobId, dbConn: dbConn)
                let staged = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(qty), 0)
                    FROM stock
                    WHERE location_type = 'pulled' AND location_id = ? AND deleted_at IS NULL
                    """, arguments: [jobId]) ?? 0
                let used = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(qty_consumed - qty_returned), 0)
                    FROM job_parts
                    WHERE job_id = ? AND deleted_at IS NULL
                    """, arguments: [jobId]) ?? 0
                let returned = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(qty_returned), 0)
                    FROM job_parts
                    WHERE job_id = ? AND deleted_at IS NULL
                    """, arguments: [jobId]) ?? 0
                let pendingReturn = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(jrii.qty_remaining), 0)
                    FROM job_return_intake_items jrii
                    JOIN job_return_intakes jri ON jri.id = jrii.intake_id
                    WHERE jri.source_job_id = ?
                      AND jri.deleted_at IS NULL
                      AND jrii.deleted_at IS NULL
                      AND jrii.status IN ('holding', 'damage_review', 'wrong_part_review', 'supplier_review')
                    """, arguments: [jobId]) ?? 0
                let netCost = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM((qty_consumed - qty_returned) * COALESCE(unit_cost_at_consume, 0)), 0)
                    FROM job_parts
                    WHERE job_id = ? AND deleted_at IS NULL
                    """, arguments: [jobId]) ?? 0
                let totalCost = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)), 0)
                    FROM job_parts
                    WHERE job_id = ? AND deleted_at IS NULL
                    """, arguments: [jobId]) ?? 0
                return JobMaterialTotals(
                    stagedQty: staged,
                    usedQty: used,
                    returnedQty: returned,
                    pendingReturnQty: pendingReturn,
                    netMaterialCost: netCost,
                    totalMaterialCost: totalCost
                )
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) {
                return JobMaterialTotals(stagedQty: 0, usedQty: 0, returnedQty: 0, pendingReturnQty: 0, netMaterialCost: 0, totalMaterialCost: 0)
            }
            throw error
        }
    }

    public func listJobMaterialHistory(jobId: Int64, limit: Int = 50) throws -> [JobMaterialHistoryRow] {
        do {
            return try db.writer.read { dbConn in
                try Self.requireActiveJob(jobId, dbConn: dbConn)
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT 'movement-' || sm.id AS row_id,
                           sm.movement_type AS event_type,
                           sm.part_id,
                           p.name AS part_name,
                           p.code AS part_code,
                           sm.qty,
                           COALESCE(u.display_name, u.email, 'User #' || sm.performed_by) AS actor_name,
                           COALESCE(sm.from_location_type, 'none') || ' -> ' || COALESCE(sm.to_location_type, 'none') AS location_summary,
                           sm.reference_number AS reference,
                           sm.notes,
                           sm.created_at
                    FROM stock_movements sm
                    LEFT JOIN parts p ON p.id = sm.part_id AND p.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = sm.performed_by AND u.deleted_at IS NULL
                    WHERE sm.job_id = ? AND sm.deleted_at IS NULL
                    UNION ALL
                    SELECT 'return-' || jrii.id AS row_id,
                           'job_return_' || jrii.status AS event_type,
                           jrii.part_id,
                           p.name AS part_name,
                           p.code AS part_code,
                           jrii.qty_returned AS qty,
                           COALESCE(u.display_name, u.email, 'User #' || jri.returned_by) AS actor_name,
                           'job -> return holding' AS location_summary,
                           'Return intake #' || jri.id AS reference,
                           jrii.notes,
                           jrii.created_at
                    FROM job_return_intake_items jrii
                    JOIN job_return_intakes jri ON jri.id = jrii.intake_id
                    LEFT JOIN parts p ON p.id = jrii.part_id AND p.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jri.returned_by AND u.deleted_at IS NULL
                    WHERE jri.source_job_id = ?
                      AND jri.deleted_at IS NULL
                      AND jrii.deleted_at IS NULL
                    ORDER BY 11 DESC, 1 DESC
                    LIMIT ?
                    """, arguments: [jobId, jobId, max(1, limit)])
                return rows.map { row in
                    JobMaterialHistoryRow(
                        id: row["row_id"] ?? "",
                        eventType: row["event_type"] ?? "material",
                        partId: row["part_id"] ?? 0,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        qty: row["qty"] ?? 0,
                        actorName: row["actor_name"] ?? "Unknown",
                        locationSummary: row["location_summary"] ?? "",
                        reference: row["reference"] as String?,
                        notes: row["notes"] as String?,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 8. Dashboard KPIs
    // =========================================================================

    /// Get jobs dashboard KPIs: active jobs, clocked-in users, today's labor hours, overdue jobs.
    public func getJobsDashboardKPIs() throws -> JobsDashboardKPIs {
        let activeJobs = try safeCount(
            sql: "SELECT COUNT(*) FROM jobs WHERE status = 'active' AND deleted_at IS NULL"
        )

        let clockedInUsers = try safeCount(
            sql: """
                SELECT COUNT(DISTINCT user_id) FROM labor_entries
                WHERE status = 'clocked_in' AND deleted_at IS NULL
                """
        )

        let todayHoursRaw = try safeCountDouble(
            sql: """
                SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
                FROM labor_entries
                WHERE \(Self.localDateSQL("clock_in")) = date('now', 'localtime') AND deleted_at IS NULL
                """
        )

        let overdueJobs = try safeCount(
            sql: """
                SELECT COUNT(*) FROM jobs
                WHERE status = 'active'
                  AND due_date IS NOT NULL
                  AND date(due_date) < date('now')
                  AND deleted_at IS NULL
                """
        )

        return JobsDashboardKPIs(
            activeJobs: activeJobs,
            clockedInUsers: clockedInUsers,
            todayLaborHours: todayHoursRaw,
            overdueJobs: overdueJobs
        )
    }

    /// Total parts cost across all jobs: sum of (qty_consumed * unit_cost_at_consume).
    public func getTotalPartsCost() throws -> Double {
        try safeCountDouble(
            sql: """
                SELECT COALESCE(SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)), 0)
                FROM job_parts WHERE deleted_at IS NULL
                """
        )
    }

    // =========================================================================
    // MARK: - 10. Active Jobs for Clock Page
    // =========================================================================

    /// A lightweight job row for the clock-in GPS-sorted picker.
    public struct ClockJobRow: Sendable, Identifiable {
        public let id: Int64
        public let jobName: String
        public let jobNumber: String
        public let address: String?
        public let latitude: Double?
        public let longitude: Double?
        public let status: String

        public init(
            id: Int64, jobName: String, jobNumber: String,
            address: String?, latitude: Double?, longitude: Double?, status: String
        ) {
            self.id = id
            self.jobName = jobName
            self.jobNumber = jobNumber
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
            self.status = status
        }
    }

    /// List active/in-progress jobs for the clock-in picker.
    /// Returns lightweight rows with address and GPS coordinates.
    /// Gracefully returns an empty array if the table or columns are missing.
    public func listActiveJobsForClock() throws -> [ClockJobRow] {
        do {
            return try db.writer.read { dbConn -> [ClockJobRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, job_name, job_number,
                           COALESCE(address_line1, '') ||
                               CASE WHEN city IS NOT NULL AND city != ''
                                    THEN ', ' || city ELSE '' END AS full_address,
                           gps_lat, gps_lng, status
                    FROM jobs
                    WHERE status IN ('active', 'in_progress')
                      AND deleted_at IS NULL
                      AND job_number != ?
                    ORDER BY job_name ASC
                    """, arguments: [Self.warehouseClockJobNumber])
                return rows.map { row in
                    ClockJobRow(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        jobNumber: row["job_number"] ?? "",
                        address: row["full_address"] as String?,
                        latitude: row["gps_lat"] as Double?,
                        longitude: row["gps_lng"] as Double?,
                        status: row["status"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) or SELECT COALESCE(SUM(...), 0) query returning an Int.
    /// Returns 0 if the table does not exist.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Execute a SELECT COALESCE(SUM(...), 0) query returning a Double.
    /// Returns 0.0 if the table does not exist.
    private func safeCountDouble(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Double {
        do {
            return try db.writer.read { dbConn in
                try Double.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0.0
            }
        } catch {
            if isTableNotFoundError(error) { return 0.0 }
            throw error
        }
    }

    private static func ensureWarehouseClockJob(dbConn: Database, createdBy: Int64?) throws -> Int64 {
        if let id = try Int64.fetchOne(
            dbConn,
            sql: "SELECT id FROM jobs WHERE job_number = ? AND deleted_at IS NULL LIMIT 1",
            arguments: [warehouseClockJobNumber]
        ) {
            return id
        }

        try dbConn.execute(
            sql: """
                INSERT INTO jobs
                (job_number, job_name, customer_name, status, priority, job_type,
                 created_by, notes, job_classification, created_at, updated_at)
                VALUES (?, ?, ?, 'active', 'normal', 'internal', ?, ?, 'internal', datetime('now'), datetime('now'))
                """,
            arguments: [
                warehouseClockJobNumber,
                warehouseClockJobName,
                "Internal",
                createdBy,
                "Internal time bucket for Shop / Warehouse clock entries."
            ]
        )
        return dbConn.lastInsertedRowID
    }

    /// List active/in-progress jobs, optionally excluding a specific job ID.
    /// Used by the geofence alert to let workers pick another job to clock into.
    public func listActiveJobs(excludingJobId: Int64? = nil) throws -> [JobListItem] {
        do {
            return try db.writer.read { dbConn -> [JobListItem] in
                var whereClauses = [
                    "j.deleted_at IS NULL",
                    "j.status IN ('active', 'in_progress')"
                ]
                var args: [DatabaseValueConvertible?] = []

                if let excludeId = excludingJobId {
                    whereClauses.append("j.id != ?")
                    args.append(excludeId)
                }

                let sql = """
                    SELECT j.id, j.job_number, j.job_name, j.customer_name,
                           j.status, j.priority, j.job_type, j.start_date, j.due_date,
                           COALESCE((SELECT COUNT(*) FROM job_team_members jtm
                                     WHERE jtm.job_id = j.id AND jtm.deleted_at IS NULL), 0) AS team_count
                    FROM jobs j
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY j.job_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    JobListItem(
                        id: row["id"] ?? 0,
                        jobNumber: row["job_number"] ?? "",
                        jobName: row["job_name"] ?? "",
                        customerName: row["customer_name"] as String?,
                        status: row["status"] ?? "active",
                        priority: row["priority"] ?? "normal",
                        jobType: row["job_type"] ?? "service",
                        teamCount: row["team_count"] ?? 0,
                        startDate: row["start_date"] as String?,
                        dueDate: row["due_date"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    private static let sqliteUTCDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func sqliteTimestamp(_ date: Date) -> String {
        sqliteUTCDateFormatter.string(from: date)
    }

    private static func parseSQLiteUTCDateTime(_ string: String) -> Date? {
        if let date = CoreFormatters.parseISO(string) { return date }
        return sqliteUTCDateFormatter.date(from: string)
    }

    /// Convert SQLite datetime/date text into the current local operational day.
    private static func localDateSQL(_ expression: String) -> String {
        "CASE WHEN length(\(expression)) <= 10 THEN date(\(expression)) ELSE date(\(expression), 'localtime') END"
    }

    @discardableResult
    private static func createClockEntry(
        dbConn: Database,
        userId: Int64,
        jobId: Int64,
        clockInTimestamp: String,
        gpsLat: Double?,
        gpsLng: Double?
    ) throws -> Int64 {
        guard let jobRow = try Row.fetchOne(
            dbConn,
            sql: "SELECT status FROM jobs WHERE id = ? AND deleted_at IS NULL",
            arguments: [jobId]
        ) else {
            throw JobsError.jobNotFound(jobId)
        }
        let jobStatus: String = jobRow["status"] ?? ""
        guard ["active", "in_progress"].contains(jobStatus) else {
            throw JobsError.jobNotClockable(jobId)
        }

        let existing = try Int.fetchOne(
            dbConn,
            sql: """
                SELECT COUNT(*) FROM labor_entries
                WHERE user_id = ? AND status = 'clocked_in' AND deleted_at IS NULL
                """,
            arguments: [userId]
        ) ?? 0
        if existing > 0 {
            throw JobsError.alreadyClockedIn(userId: userId, jobId: jobId)
        }

        try dbConn.execute(
            sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_in_gps_lat, clock_in_gps_lng, status, created_at)
                VALUES (?, ?, ?, ?, ?, 'clocked_in', ?)
                """,
            arguments: [userId, jobId, clockInTimestamp, gpsLat, gpsLng, clockInTimestamp]
        )
        return dbConn.lastInsertedRowID
    }

    @discardableResult
    private static func completeClockEntry(
        dbConn: Database,
        laborEntryId: Int64,
        clockOutTimestamp: String,
        gpsLat: Double?,
        gpsLng: Double?
    ) throws -> Int64 {
        guard let entry = try Row.fetchOne(
            dbConn,
            sql: "SELECT id, user_id, clock_in FROM labor_entries WHERE id = ? AND status = 'clocked_in' AND deleted_at IS NULL",
            arguments: [laborEntryId]
        ) else {
            throw JobsError.laborEntryNotFound(laborEntryId)
        }
        let userId: Int64 = entry["user_id"] ?? 0
        let clockIn: String = entry["clock_in"] ?? ""

        let rawHours = try Double.fetchOne(dbConn, sql: """
            SELECT ROUND((julianday(?) - julianday(clock_in)) * 24, 4)
            FROM labor_entries WHERE id = ?
            """, arguments: [clockOutTimestamp, laborEntryId]) ?? 0
        guard rawHours >= 0 else {
            throw JobsError.invalidClockOutTime(laborEntryId: laborEntryId)
        }

        let unpaidBreakMinutes = try Double.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(duration_minutes), 0)
            FROM break_records
            WHERE labor_entry_id = ? AND COALESCE(is_paid, 1) = 0 AND deleted_at IS NULL
            """, arguments: [laborEntryId]) ?? 0
        let totalHours = max(0, rawHours - (unpaidBreakMinutes / 60.0))

        let allocation = try allocateOvertimeHours(
            dbConn: dbConn,
            userId: userId,
            laborEntryId: laborEntryId,
            clockInTimestamp: clockIn,
            totalHours: totalHours
        )

        try dbConn.execute(
            sql: """
                UPDATE labor_entries
                SET clock_out = ?,
                    clock_out_gps_lat = ?,
                    clock_out_gps_lng = ?,
                    regular_hours = ROUND(?, 2),
                    overtime_hours = ROUND(?, 2),
                    status = 'completed'
                WHERE id = ?
                """,
            arguments: [clockOutTimestamp, gpsLat, gpsLng, allocation.regular, allocation.overtime, laborEntryId]
        )

        return laborEntryId
    }

    private static func fetchOvertimeSettings(_ dbConn: Database) throws -> OvertimeSettings {
        if let settings = try OvertimeSettings.fetchOne(
            dbConn,
            sql: "SELECT * FROM overtime_settings ORDER BY id LIMIT 1"
        ) {
            return settings
        }
        return OvertimeSettings(
            id: nil,
            calculationRule: "daily_only",
            dailyThresholdHours: 8.0,
            weeklyThresholdHours: nil,
            weekStartWeekday: 2,
            updatedBy: nil,
            updatedAt: nil
        )
    }

    private static func allocateOvertimeHours(
        dbConn: Database,
        userId: Int64,
        laborEntryId: Int64,
        clockInTimestamp: String,
        totalHours: Double
    ) throws -> (regular: Double, overtime: Double) {
        let settings = try fetchOvertimeSettings(dbConn)
        let dailyPriorHours = try priorCompletedHours(
            dbConn: dbConn,
            userId: userId,
            laborEntryId: laborEntryId,
            whereSQL: "\(localDateSQL("clock_in")) = date(?, 'localtime') AND clock_in < ?",
            arguments: [clockInTimestamp, clockInTimestamp]
        )
        let dailyRemaining = max(0, settings.dailyThresholdHours - dailyPriorHours)

        let weeklyRemaining: Double
        if let weeklyThresholdHours = settings.weeklyThresholdHours,
           let clockInDate = parseSQLiteUTCDateTime(clockInTimestamp) {
            let interval = localWeekInterval(containing: clockInDate, weekStartWeekday: settings.weekStartWeekday)
            let weekStart = sqliteTimestamp(interval.start)
            let weekEnd = sqliteTimestamp(interval.end)
            let weeklyPriorHours = try priorCompletedHours(
                dbConn: dbConn,
                userId: userId,
                laborEntryId: laborEntryId,
                whereSQL: "clock_in >= ? AND clock_in < ? AND clock_in < ?",
                arguments: [weekStart, weekEnd, clockInTimestamp]
            )
            weeklyRemaining = max(0, weeklyThresholdHours - weeklyPriorHours)
        } else {
            weeklyRemaining = Double.greatestFiniteMagnitude
        }

        let regularCapacity: Double
        switch settings.calculationRule {
        case "weekly_only":
            regularCapacity = weeklyRemaining
        case "daily_and_weekly":
            regularCapacity = min(dailyRemaining, weeklyRemaining)
        default:
            regularCapacity = dailyRemaining
        }

        let regularHours = min(totalHours, max(0, regularCapacity))
        let overtimeHours = max(0, totalHours - regularHours)
        return (roundHours(regularHours), roundHours(overtimeHours))
    }

    private static func priorCompletedHours(
        dbConn: Database,
        userId: Int64,
        laborEntryId: Int64,
        whereSQL: String,
        arguments: StatementArguments
    ) throws -> Double {
        var allArguments: StatementArguments = [userId, laborEntryId]
        allArguments += arguments
        return try Double.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
            FROM labor_entries
            WHERE user_id = ?
              AND id != ?
              AND status = 'completed'
              AND deleted_at IS NULL
              AND \(whereSQL)
            """, arguments: allArguments) ?? 0
    }

    private static func localWeekInterval(containing date: Date, weekStartWeekday: Int) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = weekStartWeekday

        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysSinceStart = (weekday - weekStartWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -daysSinceStart, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private static func roundHours(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func requireActiveUser(_ dbConn: Database, userId: Int64) throws {
        let count = try Int.fetchOne(
            dbConn,
            sql: "SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND COALESCE(is_active, 1) = 1",
            arguments: [userId]
        ) ?? 0
        guard count > 0 else { throw JobsError.userNotActive(userId) }
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }

    /// Detect whether a GRDB/SQLite error indicates a missing column.
    private func isColumnNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such column")
    }

    // MARK: - Supply Run

    /// Toggles supply run status on a labor entry by appending a timestamped marker to notes.
    /// Returns the new activity status ("supply_run" or "working").
    @discardableResult
    public func toggleSupplyRun(laborEntryId: Int64) throws -> String {
        try db.writer.write { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT notes FROM labor_entries WHERE id = ? AND deleted_at IS NULL",
                arguments: [laborEntryId]
            ) else { return "working" }

            let existingNotes: String = row["notes"] ?? ""
            let timestamp = CoreFormatters.nowISO()
            let isCurrentlyOnRun = Self.isOnSupplyRun(notes: existingNotes)

            let note: String
            if !isCurrentlyOnRun {
                note = existingNotes.isEmpty
                    ? "[supply_run_start:\(timestamp)]"
                    : "\(existingNotes) [supply_run_start:\(timestamp)]"
            } else {
                note = "\(existingNotes) [supply_run_end:\(timestamp)]"
            }

            try conn.execute(
                sql: "UPDATE labor_entries SET notes = ? WHERE id = ? AND deleted_at IS NULL",
                arguments: [note, laborEntryId]
            )

            return isCurrentlyOnRun ? "working" : "supply_run"
        }
    }

    /// Returns the notes field for a labor entry.
    public func getLaborEntryNotes(laborEntryId: Int64) throws -> String? {
        try db.writer.read { conn in
            try String.fetchOne(
                conn,
                sql: "SELECT notes FROM labor_entries WHERE id = ? AND deleted_at IS NULL",
                arguments: [laborEntryId]
            )
        }
    }

    /// Checks if the supply run markers in a notes string indicate an active supply run.
    public static func isOnSupplyRun(notes: String?) -> Bool {
        guard let notes, notes.contains("[supply_run_start:") else { return false }
        let lastStart = notes.range(of: "[supply_run_start:", options: .backwards)
        let lastEnd = notes.range(of: "[supply_run_end:", options: .backwards)
        if let start = lastStart {
            if let end = lastEnd {
                return start.lowerBound > end.lowerBound
            }
            return true
        }
        return false
    }

    // =========================================================================
    // MARK: - Job Stages
    // =========================================================================

    /// Get all job stages with computed status relative to a specific job's progression.
    ///
    /// - If the job has no `current_stage_id`, all stages are "pending" (job hasn't started staging).
    /// - Stages before the current stage are "completed".
    /// - The current stage is "in_progress".
    /// - Stages after the current stage are "pending".
    /// - If the job status is "completed", all stages are marked "completed".
    public func listJobStages(forJobId jobId: Int64) throws -> [JobStageStatus] {
        do {
            return try db.writer.read { dbConn -> [JobStageStatus] in
                // Get the job's assigned template, current_stage_id, and status.
                guard let jobRow = try Row.fetchOne(dbConn, sql: """
                    SELECT current_stage_id, stage_template_id, status FROM jobs WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [jobId]) else {
                    return []
                }

                let currentStageId: Int64? = jobRow["current_stage_id"]
                let templateId: Int64? = jobRow["stage_template_id"]
                let jobStatus: String = jobRow["status"] ?? "active"

                // Get stages for the assigned template. Older databases without templates fall back to global stages.
                let stageRows: [Row]
                if let templateId {
                    stageRows = try Row.fetchAll(dbConn, sql: """
                        SELECT id, name, sort_order FROM job_stages
                        WHERE deleted_at IS NULL AND template_id = ?
                        ORDER BY sort_order ASC, id ASC
                        """, arguments: [templateId])
                } else {
                    stageRows = try Row.fetchAll(dbConn, sql: """
                        SELECT id, name, sort_order FROM job_stages
                        WHERE deleted_at IS NULL
                        ORDER BY sort_order ASC, id ASC
                        """)
                }

                guard !stageRows.isEmpty else { return [] }

                // If job is completed, all stages are completed
                if jobStatus == "completed" {
                    return stageRows.map { row in
                        JobStageStatus(
                            id: row["id"] ?? 0,
                            name: row["name"] ?? "",
                            sortOrder: row["sort_order"] ?? 0,
                            status: "completed"
                        )
                    }
                }

                // No current stage set — all pending
                guard let currentId = currentStageId else {
                    return stageRows.map { row in
                        JobStageStatus(
                            id: row["id"] ?? 0,
                            name: row["name"] ?? "",
                            sortOrder: row["sort_order"] ?? 0,
                            status: "pending"
                        )
                    }
                }

                // Get current stage's sort_order
                let currentSortOrder: Int = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(sort_order, 0) FROM job_stages WHERE id = ?
                    """, arguments: [currentId]) ?? 0

                return stageRows.map { row in
                    let stageId: Int64 = row["id"] ?? 0
                    let sortOrder: Int = row["sort_order"] ?? 0
                    let status: String
                    if sortOrder < currentSortOrder {
                        status = "completed"
                    } else if stageId == currentId {
                        status = "in_progress"
                    } else {
                        status = "pending"
                    }
                    return JobStageStatus(
                        id: stageId,
                        name: row["name"] ?? "",
                        sortOrder: sortOrder,
                        status: status
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get job stages without job-specific status. Pass a template to avoid cross-template leakage.
    /// Returns stages ordered by sort_order.
    public func listAllJobStages(templateId: Int64? = nil) throws -> [JobStageStatus] {
        do {
            return try db.writer.read { dbConn -> [JobStageStatus] in
                let rows: [Row]
                if let templateId {
                    rows = try Row.fetchAll(dbConn, sql: """
                        SELECT id, name, sort_order FROM job_stages
                        WHERE deleted_at IS NULL AND template_id = ?
                        ORDER BY sort_order ASC, id ASC
                        """, arguments: [templateId])
                } else {
                    rows = try Row.fetchAll(dbConn, sql: """
                        SELECT id, name, sort_order FROM job_stages
                        WHERE deleted_at IS NULL
                        ORDER BY sort_order ASC, id ASC
                        """)
                }
                return rows.map { row in
                    JobStageStatus(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        sortOrder: row["sort_order"] ?? 0,
                        status: "pending"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) || isColumnNotFoundError(error) { return [] }
            throw error
        }
    }

    public func listJobStageTemplates(includeArchived: Bool = false) throws -> [JobStageTemplate] {
        do {
            return try db.writer.read { dbConn in
                let archivedClause = includeArchived ? "" : "WHERE t.archived_at IS NULL"
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT t.id, t.name, t.is_default, t.archived_at,
                           COUNT(DISTINCT s.id) AS stage_count,
                           COUNT(DISTINCT CASE
                               WHEN j.deleted_at IS NULL AND j.status NOT IN ('completed', 'cancelled') THEN j.id
                           END) AS active_job_count
                    FROM job_stage_templates t
                    LEFT JOIN job_stages s ON s.template_id = t.id AND s.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.stage_template_id = t.id
                    \(archivedClause)
                    GROUP BY t.id, t.name, t.is_default, t.archived_at
                    ORDER BY t.is_default DESC, t.name COLLATE NOCASE ASC
                    """)
                return rows.map { row in
                    JobStageTemplate(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        isDefault: ((row["is_default"] as Int?) ?? 0) != 0,
                        archivedAt: row["archived_at"],
                        stageCount: row["stage_count"] ?? 0,
                        activeJobCount: row["active_job_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    @discardableResult
    public func createJobStageTemplate(name: String, stageNames: [String]) throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobsError.requiredFieldEmpty }
        let cleanStageNames = stageNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cleanStageNames.allSatisfy({ !$0.isEmpty }) else { throw JobsError.requiredFieldEmpty }

        return try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO job_stage_templates (name, is_default, created_at, updated_at)
                VALUES (?, 0, datetime('now'), datetime('now'))
                """, arguments: [trimmed])
            let templateId = dbConn.lastInsertedRowID
            for (index, stageName) in cleanStageNames.enumerated() {
                try dbConn.execute(sql: """
                    INSERT INTO job_stages (template_id, name, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, datetime('now'), datetime('now'))
                    """, arguments: [templateId, stageName, index + 1])
            }
            return templateId
        }
    }

    public func renameJobStageTemplate(templateId: Int64, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobsError.requiredFieldEmpty }
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE job_stage_templates SET name = ?, updated_at = datetime('now')
                WHERE id = ? AND archived_at IS NULL
                """, arguments: [trimmed, templateId])
            if dbConn.changesCount == 0 { throw JobsError.templateNotFound(templateId) }
        }
    }

    public func archiveJobStageTemplate(templateId: Int64) throws {
        try db.writer.write { dbConn in
            let activeJobs = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM jobs
                WHERE stage_template_id = ? AND deleted_at IS NULL AND status NOT IN ('completed', 'cancelled')
                """, arguments: [templateId]) ?? 0
            if activeJobs > 0 { throw JobsError.invalidStageTemplate(templateId) }
            try dbConn.execute(sql: """
                UPDATE job_stage_templates SET archived_at = datetime('now'), updated_at = datetime('now')
                WHERE id = ? AND is_default = 0 AND archived_at IS NULL
                """, arguments: [templateId])
            if dbConn.changesCount == 0 { throw JobsError.templateNotFound(templateId) }
        }
    }

    @discardableResult
    public func duplicateJobStageTemplate(templateId: Int64, name: String) throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobsError.requiredFieldEmpty }
        return try db.writer.write { dbConn in
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stage_templates WHERE id = ? AND archived_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.templateNotFound(templateId)
            }
            try dbConn.execute(sql: """
                INSERT INTO job_stage_templates (name, is_default, created_at, updated_at)
                VALUES (?, 0, datetime('now'), datetime('now'))
                """, arguments: [trimmed])
            let newTemplateId = dbConn.lastInsertedRowID
            try dbConn.execute(sql: """
                INSERT INTO job_stages (template_id, name, sort_order, created_at, updated_at)
                SELECT ?, name, sort_order, datetime('now'), datetime('now')
                FROM job_stages
                WHERE template_id = ? AND deleted_at IS NULL
                ORDER BY sort_order ASC, id ASC
                """, arguments: [newTemplateId, templateId])
            return newTemplateId
        }
    }

    @discardableResult
    public func addJobStage(templateId: Int64, name: String) throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobsError.requiredFieldEmpty }
        return try db.writer.write { dbConn in
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stage_templates WHERE id = ? AND archived_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.templateNotFound(templateId)
            }
            let nextSort = (try Int.fetchOne(dbConn, sql: "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM job_stages WHERE template_id = ? AND deleted_at IS NULL", arguments: [templateId]) ?? 1)
            try dbConn.execute(sql: """
                INSERT INTO job_stages (template_id, name, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, datetime('now'), datetime('now'))
                """, arguments: [templateId, trimmed, nextSort])
            return dbConn.lastInsertedRowID
        }
    }

    public func renameJobStage(stageId: Int64, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobsError.requiredFieldEmpty }
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE job_stages SET name = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [trimmed, stageId])
            if dbConn.changesCount == 0 { throw JobsError.stageNotFound(stageId) }
        }
    }

    public func archiveJobStage(stageId: Int64) throws {
        try db.writer.write { dbConn in
            let references = try Int.fetchOne(dbConn, sql: """
                SELECT
                    (SELECT COUNT(*) FROM jobs WHERE current_stage_id = ? AND deleted_at IS NULL AND status NOT IN ('completed', 'cancelled')) +
                    (SELECT COUNT(*) FROM jpo_line_items WHERE stage_id = ?) +
                    (SELECT COUNT(*) FROM job_stage_category_map WHERE stage_id = ?)
                """, arguments: [stageId, stageId, stageId]) ?? 0
            if references > 0 { throw JobsError.stageInUse(stageId) }
            try dbConn.execute(sql: """
                UPDATE job_stages SET deleted_at = datetime('now'), updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [stageId])
            if dbConn.changesCount == 0 { throw JobsError.stageNotFound(stageId) }
        }
    }

    public func reorderJobStages(templateId: Int64, orderedStageIds: [Int64]) throws {
        try db.writer.write { dbConn in
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stage_templates WHERE id = ? AND archived_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.templateNotFound(templateId)
            }
            let existingIds = try Int64.fetchAll(dbConn, sql: """
                SELECT id FROM job_stages
                WHERE template_id = ? AND deleted_at IS NULL
                ORDER BY sort_order ASC, id ASC
                """, arguments: [templateId])
            guard Set(existingIds) == Set(orderedStageIds), existingIds.count == orderedStageIds.count else {
                throw JobsError.invalidStageTemplate(templateId)
            }
            for (index, stageId) in orderedStageIds.enumerated() {
                try dbConn.execute(sql: """
                    UPDATE job_stages SET sort_order = ?, updated_at = datetime('now')
                    WHERE id = ? AND template_id = ?
                    """, arguments: [-(index + 1), stageId, templateId])
            }
            for (index, stageId) in orderedStageIds.enumerated() {
                try dbConn.execute(sql: """
                    UPDATE job_stages SET sort_order = ?, updated_at = datetime('now')
                    WHERE id = ? AND template_id = ?
                    """, arguments: [index + 1, stageId, templateId])
            }
        }
    }

    /// Applies the complete staged editor draft for a job-stage template as a single atomic unit.
    ///
    /// The draft list is the desired final active stage list in display order. Existing stages not
    /// present in the draft are archived, kept stages are renamed, nil-id rows are inserted, and the
    /// final kept/new set is reordered. Any validation or database failure rolls back the whole save
    /// so the UI's Save/Cancel model cannot leave partial archive/rename/add/reorder changes behind.
    public func applyJobStageTemplateDraft(templateId: Int64, stages draftStages: [JobStageTemplateDraftStage]) throws {
        let cleaned = draftStages.map { draft in
            JobStageTemplateDraftStage(
                existingId: draft.existingId,
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !cleaned.isEmpty else { throw JobsError.invalidStageTemplate(templateId) }
        guard cleaned.allSatisfy({ !$0.name.isEmpty }) else { throw JobsError.requiredFieldEmpty }

        try db.writer.write { dbConn in
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stage_templates WHERE id = ? AND archived_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.templateNotFound(templateId)
            }

            let originalIds = try Int64.fetchAll(dbConn, sql: """
                SELECT id FROM job_stages
                WHERE template_id = ? AND deleted_at IS NULL
                ORDER BY sort_order ASC, id ASC
                """, arguments: [templateId])
            let originalIdSet = Set(originalIds)
            let keptExistingIds = cleaned.compactMap(\.existingId)
            guard keptExistingIds.allSatisfy({ originalIdSet.contains($0) }) else {
                throw JobsError.invalidStageTemplate(templateId)
            }

            let removedIds = originalIds.filter { !Set(keptExistingIds).contains($0) }
            for stageId in removedIds {
                let references = try Int.fetchOne(dbConn, sql: """
                    SELECT
                        (SELECT COUNT(*) FROM jobs WHERE current_stage_id = ? AND deleted_at IS NULL AND status NOT IN ('completed', 'cancelled')) +
                        (SELECT COUNT(*) FROM jpo_line_items WHERE stage_id = ?) +
                        (SELECT COUNT(*) FROM job_stage_category_map WHERE stage_id = ?)
                    """, arguments: [stageId, stageId, stageId]) ?? 0
                if references > 0 { throw JobsError.stageInUse(stageId) }
                try dbConn.execute(sql: """
                    UPDATE job_stages SET deleted_at = datetime('now'), updated_at = datetime('now')
                    WHERE id = ? AND template_id = ? AND deleted_at IS NULL
                    """, arguments: [stageId, templateId])
                if dbConn.changesCount == 0 { throw JobsError.stageNotFound(stageId) }
            }

            var orderedIds: [Int64] = []
            for (index, draft) in cleaned.enumerated() {
                let stagedSortOrder = -100_000 - index
                if let stageId = draft.existingId {
                    try dbConn.execute(sql: """
                        UPDATE job_stages SET name = ?, sort_order = ?, updated_at = datetime('now')
                        WHERE id = ? AND template_id = ? AND deleted_at IS NULL
                        """, arguments: [draft.name, stagedSortOrder, stageId, templateId])
                    if dbConn.changesCount == 0 { throw JobsError.stageNotFound(stageId) }
                    orderedIds.append(stageId)
                } else {
                    try dbConn.execute(sql: """
                        INSERT INTO job_stages (template_id, name, sort_order, created_at, updated_at)
                        VALUES (?, ?, ?, datetime('now'), datetime('now'))
                        """, arguments: [templateId, draft.name, stagedSortOrder])
                    orderedIds.append(dbConn.lastInsertedRowID)
                }
            }

            guard Set(orderedIds).count == orderedIds.count else {
                throw JobsError.invalidStageTemplate(templateId)
            }
            for (index, stageId) in orderedIds.enumerated() {
                try dbConn.execute(sql: """
                    UPDATE job_stages SET sort_order = ?, updated_at = datetime('now')
                    WHERE id = ? AND template_id = ? AND deleted_at IS NULL
                    """, arguments: [index + 1, stageId, templateId])
                if dbConn.changesCount == 0 { throw JobsError.stageNotFound(stageId) }
            }
        }
    }

    public func previewJobStageTemplateAssignment(jobId: Int64, templateId: Int64) throws -> JobStageTemplateAssignmentPreview {
        try db.writer.read { dbConn in
            guard let jobRow = try Row.fetchOne(dbConn, sql: "SELECT stage_template_id, current_stage_id FROM jobs WHERE id = ? AND deleted_at IS NULL", arguments: [jobId]) else {
                throw JobsError.jobNotFound(jobId)
            }
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stage_templates WHERE id = ? AND archived_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.templateNotFound(templateId)
            }
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stages WHERE template_id = ? AND deleted_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.invalidStageTemplate(templateId)
            }
            let currentTemplateId: Int64? = jobRow["stage_template_id"]
            let currentStageId: Int64? = jobRow["current_stage_id"]
            let stageStillBelongs: Int
            if let currentStageId {
                stageStillBelongs = try Int.fetchOne(
                    dbConn,
                    sql: "SELECT COUNT(*) FROM job_stages WHERE id = ? AND template_id = ? AND deleted_at IS NULL",
                    arguments: [currentStageId, templateId]
                ) ?? 0
            } else {
                stageStillBelongs = 0
            }
            let replacementStageId: Int64?
            let preservesCurrentStage = stageStillBelongs > 0
            if preservesCurrentStage {
                replacementStageId = currentStageId
            } else {
                replacementStageId = try Int64.fetchOne(dbConn, sql: """
                    SELECT id FROM job_stages
                    WHERE template_id = ? AND deleted_at IS NULL
                    ORDER BY sort_order ASC, id ASC LIMIT 1
                    """, arguments: [templateId])
            }
            return JobStageTemplateAssignmentPreview(
                jobId: jobId,
                currentTemplateId: currentTemplateId,
                nextTemplateId: templateId,
                currentStageId: currentStageId,
                replacementStageId: replacementStageId,
                preservesCurrentStage: preservesCurrentStage
            )
        }
    }

    public func assignJobStageTemplate(jobId: Int64, templateId: Int64, currentStageId: Int64? = nil) throws {
        try db.writer.write { dbConn in
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL", arguments: [jobId]) ?? 0 > 0 else {
                throw JobsError.jobNotFound(jobId)
            }
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stage_templates WHERE id = ? AND archived_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.templateNotFound(templateId)
            }
            let assignedStageId: Int64
            if let currentStageId {
                guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stages WHERE id = ? AND template_id = ? AND deleted_at IS NULL", arguments: [currentStageId, templateId]) ?? 0 > 0 else {
                    throw JobsError.stageNotFound(currentStageId)
                }
                assignedStageId = currentStageId
            } else if let firstStageId = try Int64.fetchOne(dbConn, sql: "SELECT id FROM job_stages WHERE template_id = ? AND deleted_at IS NULL ORDER BY sort_order ASC, id ASC LIMIT 1", arguments: [templateId]) {
                assignedStageId = firstStageId
            } else {
                throw JobsError.invalidStageTemplate(templateId)
            }
            try dbConn.execute(sql: """
                UPDATE jobs
                SET stage_template_id = ?, current_stage_id = ?, updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [templateId, assignedStageId, jobId])
        }
    }

    /// Move a job to a stage in its assigned template and append an audit entry to the job notebook.
    public func updateJobStage(jobId: Int64, stageId: Int64, changedBy: Int64, note: String? = nil) throws {
        try db.writer.write { dbConn in
            guard let jobRow = try Row.fetchOne(dbConn, sql: """
                SELECT id, stage_template_id, current_stage_id
                FROM jobs
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId]) else {
                throw JobsError.jobNotFound(jobId)
            }

            let templateId: Int64? = jobRow["stage_template_id"]
            let currentStageId: Int64? = jobRow["current_stage_id"]
            let stageSql: String
            let stageArgs: [DatabaseValueConvertible?]
            if let templateId {
                stageSql = "SELECT id, name FROM job_stages WHERE id = ? AND template_id = ? AND deleted_at IS NULL"
                stageArgs = [stageId, templateId]
            } else {
                stageSql = "SELECT id, name FROM job_stages WHERE id = ? AND deleted_at IS NULL"
                stageArgs = [stageId]
            }
            guard let nextStage = try Row.fetchOne(dbConn, sql: stageSql, arguments: StatementArguments(stageArgs)) else {
                throw JobsError.stageNotFound(stageId)
            }

            let previousName: String
            if let currentStageId,
               let previous = try String.fetchOne(dbConn, sql: "SELECT name FROM job_stages WHERE id = ?", arguments: [currentStageId]) {
                previousName = previous
            } else {
                previousName = "Unassigned"
            }
            let nextName: String = nextStage["name"] ?? "Stage #\(stageId)"
            guard currentStageId != stageId else { return }

            try dbConn.execute(sql: """
                UPDATE jobs
                SET current_stage_id = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [stageId, jobId])

            let content = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let auditContent = content?.isEmpty == false ? content : "Changed from \(previousName) to \(nextName)."
            _ = try Self.insertJobNotebookEntry(
                dbConn,
                jobId: jobId,
                title: "Stage changed: \(previousName) -> \(nextName)",
                content: auditContent,
                entryType: "stage_change",
                createdBy: changedBy
            )
        }
    }

    public func setJobStageCategoryMapping(templateId: Int64, categoryId: Int64, stageId: Int64?) throws {
        try db.writer.write { dbConn in
            guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stage_templates WHERE id = ? AND archived_at IS NULL", arguments: [templateId]) ?? 0 > 0 else {
                throw JobsError.templateNotFound(templateId)
            }
            if let stageId {
                guard try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM job_stages WHERE id = ? AND template_id = ? AND deleted_at IS NULL", arguments: [stageId, templateId]) ?? 0 > 0 else {
                    throw JobsError.stageNotFound(stageId)
                }
                try dbConn.execute(sql: """
                    INSERT INTO job_stage_category_map (template_id, stage_id, category_id, created_at, updated_at)
                    VALUES (?, ?, ?, datetime('now'), datetime('now'))
                    ON CONFLICT(template_id, category_id) DO UPDATE SET
                        stage_id = excluded.stage_id,
                        updated_at = datetime('now')
                    """, arguments: [templateId, stageId, categoryId])
            } else {
                try dbConn.execute(sql: "DELETE FROM job_stage_category_map WHERE template_id = ? AND category_id = ?", arguments: [templateId, categoryId])
            }
        }
    }

    public func listJobStageCategoryMappings(templateId: Int64) throws -> [JobStageCategoryMapping] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT pc.id AS category_id, pc.name AS category_name,
                       jscm.id AS mapping_id, jscm.stage_id, js.name AS stage_name
                FROM part_categories pc
                LEFT JOIN job_stage_category_map jscm
                    ON jscm.category_id = pc.id AND jscm.template_id = ?
                LEFT JOIN job_stages js
                    ON js.id = jscm.stage_id AND js.deleted_at IS NULL
                WHERE pc.deleted_at IS NULL
                ORDER BY pc.name COLLATE NOCASE ASC, pc.id ASC
                """, arguments: [templateId])
            return rows.map { row in
                let categoryId: Int64 = row["category_id"] ?? 0
                return JobStageCategoryMapping(
                    id: row["mapping_id"] ?? -categoryId,
                    templateId: templateId,
                    categoryId: categoryId,
                    categoryName: row["category_name"] ?? "",
                    stageId: row["stage_id"],
                    stageName: row["stage_name"]
                )
            }
        }
    }

    /// Compute stage statuses from a currentStageId against a list of all stages.
    /// Used to avoid re-querying the DB when stages are already loaded.
    public static func computeStageStatuses(
        allStages: [JobStageStatus],
        currentStageId: Int64?,
        jobStatus: String
    ) -> [JobStageStatus] {
        // If job is completed, all stages are completed
        if jobStatus == "completed" {
            return allStages.map {
                JobStageStatus(id: $0.id, name: $0.name, sortOrder: $0.sortOrder, status: "completed")
            }
        }
        guard let currentId = currentStageId else {
            // No stage set — all pending
            return allStages
        }
        let currentSortOrder = allStages.first(where: { $0.id == currentId })?.sortOrder ?? 0
        return allStages.map { stage in
            let status: String
            if stage.sortOrder < currentSortOrder {
                status = "completed"
            } else if stage.id == currentId {
                status = "in_progress"
            } else {
                status = "pending"
            }
            return JobStageStatus(id: stage.id, name: stage.name, sortOrder: stage.sortOrder, status: status)
        }
    }

    private static func requireActiveJob(_ jobId: Int64, dbConn: Database) throws {
        let exists = (try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL
            """, arguments: [jobId]) ?? 0) > 0
        guard exists else { throw JobsError.jobNotFound(jobId) }
    }

    private static func requireActivePart(_ partId: Int64, dbConn: Database) throws {
        let exists = (try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM parts WHERE id = ? AND deleted_at IS NULL
            """, arguments: [partId]) ?? 0) > 0
        guard exists else { throw JobsError.partNotFound(partId) }
    }

    private static func requireActiveUser(_ userId: Int64, dbConn: Database) throws {
        let exists = (try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL
            """, arguments: [userId]) ?? 0) > 0
        guard exists else { throw JobsError.userNotFound(userId) }
    }

    private static func stockQty(partId: Int64, locationType: String, locationId: Int64, dbConn: Database) throws -> Int {
        try Int.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(qty), 0)
            FROM stock
            WHERE part_id = ?
              AND location_type = ?
              AND location_id = ?
              AND deleted_at IS NULL
            """, arguments: [partId, locationType, locationId]) ?? 0
    }

    private static func latestStagedUnitCost(partId: Int64, jobId: Int64, dbConn: Database) throws -> Double? {
        try Double.fetchOne(dbConn, sql: """
            SELECT unit_cost_at_move
            FROM stock_movements
            WHERE part_id = ?
              AND to_location_type = 'pulled'
              AND to_location_id = ?
              AND job_id = ?
              AND deleted_at IS NULL
              AND unit_cost_at_move IS NOT NULL
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """, arguments: [partId, jobId, jobId])
    }

    private static func decrementStock(partId: Int64, locationType: String, locationId: Int64, qty: Int, dbConn: Database) throws {
        let available = try stockQty(partId: partId, locationType: locationType, locationId: locationId, dbConn: dbConn)
        guard available >= qty else {
            throw JobsError.insufficientStagedMaterial(available: available, requested: qty)
        }
        try dbConn.execute(sql: """
            UPDATE stock
            SET qty = qty - ?, updated_at = datetime('now')
            WHERE part_id = ?
              AND location_type = ?
              AND location_id = ?
              AND deleted_at IS NULL
            """, arguments: [qty, partId, locationType, locationId])
    }

    private static func incrementStock(partId: Int64, locationType: String, locationId: Int64, qty: Int, dbConn: Database) throws {
        try dbConn.execute(sql: """
            UPDATE stock
            SET qty = qty + ?, updated_at = datetime('now')
            WHERE part_id = ?
              AND location_type = ?
              AND location_id = ?
              AND deleted_at IS NULL
            """, arguments: [qty, partId, locationType, locationId])
        if dbConn.changesCount == 0 {
            try dbConn.execute(sql: """
                INSERT INTO stock (part_id, location_type, location_id, qty, updated_at)
                VALUES (?, ?, ?, ?, datetime('now'))
                """, arguments: [partId, locationType, locationId, qty])
        }
    }

    @discardableResult
    private static func insertStockMovement(
        partId: Int64,
        qty: Int,
        fromLocationType: String?,
        fromLocationId: Int64?,
        toLocationType: String?,
        toLocationId: Int64?,
        movementType: String,
        reason: String?,
        notes: String?,
        performedBy: Int64,
        jobId: Int64,
        unitCostAtMove: Double?,
        dbConn: Database
    ) throws -> Int64 {
        try dbConn.execute(sql: """
            INSERT INTO stock_movements
                (part_id, qty, from_location_type, from_location_id,
                 to_location_type, to_location_id, movement_type,
                 reason, notes, performed_by, job_id, unit_cost_at_move, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            """, arguments: [
                partId, qty, fromLocationType, fromLocationId,
                toLocationType, toLocationId, movementType,
                reason, notes, performedBy, jobId, unitCostAtMove,
            ])
        return dbConn.lastInsertedRowID
    }

    @discardableResult
    private static func insertJobReturnIntake(
        sourceJobId: Int64,
        returnSource: String,
        returnedBy: Int64,
        partId: Int64,
        qty: Int,
        condition: String,
        sourceJobPartId: Int64?,
        notes: String?,
        dbConn: Database
    ) throws -> Int64 {
        let normalizedCondition = normalizeReturnCondition(condition)
        let itemStatus = initialReturnItemStatus(condition: normalizedCondition)
        try dbConn.execute(sql: """
            INSERT INTO job_return_intakes
                (source_job_id, return_source, returned_by, status, notes, created_at, updated_at)
            VALUES (?, ?, ?, 'holding', ?, datetime('now'), datetime('now'))
            """, arguments: [sourceJobId, returnSource, returnedBy, notes])
        let intakeId = dbConn.lastInsertedRowID

        try dbConn.execute(sql: """
            INSERT INTO job_return_intake_items
                (intake_id, part_id, source_job_part_id, qty_returned, qty_remaining,
                 condition, status, notes, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            """, arguments: [
                intakeId, partId, sourceJobPartId, qty, qty,
                normalizedCondition, itemStatus, notes,
            ])

        return intakeId
    }

    private static func normalizeReturnCondition(_ condition: String) -> String {
        let normalized = condition
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return normalized.isEmpty ? "usable" : normalized
    }

    private static func initialReturnItemStatus(condition: String) -> String {
        switch condition {
        case "damaged":
            return "damage_review"
        case "wrong_part":
            return "wrong_part_review"
        case "supplier_issue":
            return "supplier_review"
        default:
            return "holding"
        }
    }

    private static func insertJobNotebookEntry(
        _ dbConn: Database,
        jobId: Int64,
        title: String,
        content: String?,
        entryType: String,
        createdBy: Int64
    ) throws -> Int64 {
        let jobName = try String.fetchOne(
            dbConn,
            sql: "SELECT job_name FROM jobs WHERE id = ? AND deleted_at IS NULL",
            arguments: [jobId]
        ) ?? "Job \(jobId)"
        let notebookId: Int64
        if let existingNotebookId = try Int64.fetchOne(dbConn, sql: """
            SELECT id FROM notebooks
            WHERE job_id = ? AND deleted_at IS NULL
            ORDER BY id ASC LIMIT 1
            """, arguments: [jobId]) {
            notebookId = existingNotebookId
        } else {
            try dbConn.execute(sql: """
                INSERT INTO notebooks (title, description, job_id, created_by, notebook_type, status, created_at, updated_at)
                VALUES (?, 'Auto-created job activity notebook', ?, ?, 'job', 'active', datetime('now'), datetime('now'))
                """, arguments: ["\(jobName) Notebook", jobId, createdBy])
            notebookId = dbConn.lastInsertedRowID
        }

        let sectionId: Int64
        if let existingSectionId = try Int64.fetchOne(dbConn, sql: """
            SELECT id FROM notebook_sections
            WHERE notebook_id = ? AND name = 'Notes' AND deleted_at IS NULL
            ORDER BY id ASC LIMIT 1
            """, arguments: [notebookId]) {
            sectionId = existingSectionId
        } else {
            try dbConn.execute(sql: """
                INSERT INTO notebook_sections (notebook_id, name, section_type, sort_order, created_at)
                VALUES (?, 'Notes', 'notes', 0, datetime('now'))
                """, arguments: [notebookId])
            sectionId = dbConn.lastInsertedRowID
        }

        try dbConn.execute(sql: """
            INSERT INTO notebook_entries
                (section_id, title, content, entry_type, created_by, updated_by, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 0, datetime('now'), datetime('now'))
            """, arguments: [sectionId, title, content, entryType, createdBy, createdBy])
        let entryId = dbConn.lastInsertedRowID
        try dbConn.execute(sql: "UPDATE notebooks SET updated_at = datetime('now') WHERE id = ?", arguments: [notebookId])
        return entryId
    }
}
