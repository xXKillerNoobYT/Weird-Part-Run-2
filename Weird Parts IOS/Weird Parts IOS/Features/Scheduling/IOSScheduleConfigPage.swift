import SwiftUI
import WiredPartCore

/// Global schedule configuration page.
///
/// Manages company work hours, shift templates, holidays,
/// dispatch rules, and supervisor settings.
struct IOSScheduleConfigPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Company Work Hours

    @State private var workDayStart = Date.timeOnly(hour: 7, minute: 0)
    @State private var workDayEnd = Date.timeOnly(hour: 17, minute: 0)
    @State private var lunchDuration = 30
    @State private var lunchPaid = false
    @State private var workDays: Set<String> = ["mon", "tue", "wed", "thu", "fri"]
    @State private var overtimeMode = "weekly"  // "daily" or "weekly"
    @State private var overtimeThreshold = 40
    @State private var defaultBreakMinutes = 15
    @State private var enableWeekendScheduling = false

    // MARK: - Shift Templates

    @State private var shiftTemplates: [SchedulingService.ShiftTemplateRow] = []

    // MARK: - Holidays

    @State private var holidays: [SchedulingService.HolidayRow] = []

    // MARK: - Dispatch Rules

    @State private var minNoticeHours = 24
    @State private var maxHoursPerDay = 10
    @State private var requireOvertimeApproval = false

    // MARK: - Supervisor Settings

    @State private var allHats: [PeopleService.HatListItem] = []
    @State private var supervisorHatIds: Set<Int64> = []
    @State private var supervisorSeeOwnTeamOnly = true
    @State private var supervisorCanApproveTimeOff = true

    // MARK: - UI State

    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    @State private var saveError: String?
    @State private var loadErrorMsg: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        case editShiftTemplate(SchedulingService.ShiftTemplateRow?)
        case editHoliday(SchedulingService.HolidayRow?)

        var id: String {
            switch self {
            case .help: "help"
            case .editShiftTemplate(let t): "shiftTemplate-\(t?.id ?? 0)"
            case .editHoliday(let h): "holiday-\(h?.id ?? 0)"
            }
        }
    }

    private let dayOrder = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private let dayLabels = ["M", "T", "W", "Th", "F", "Sa", "Su"]

    var body: some View {
        Form {
            companyWorkHoursSection
            shiftTemplatesSection
            holidaysSection
            dispatchRulesSection
            supervisorSection
            saveSection

            if let error = saveError ?? loadErrorMsg {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Schedule Config")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .task { loadAll() }
        .alert("Configuration Saved", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - Sheet Router

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .help:
            PageHelpSheet(title: "Schedule Config Help", sections: [
                ("Company Work Hours", "Set default start/end times, work days, lunch breaks, and overtime thresholds for your company."),
                ("Shift Templates", "Create role-based shift definitions. Each template ties to a job hat (role) and defines specific hours."),
                ("Holidays", "Define company holidays. Paid holidays are included in payroll calculations."),
                ("Dispatch Rules", "Set minimum notice for assignments, daily hour limits, and overtime approval requirements."),
                ("Supervisor Settings", "Choose which hats (roles) act as supervisors and what they can see and approve.")
            ])
        case .editShiftTemplate(let existing):
            ShiftTemplateEditSheet(
                existing: existing,
                hats: allHats,
                onSave: { saveShiftTemplate($0) },
                onDelete: existing.map { tpl in { deleteShiftTemplate(tpl.id) } }
            )
            .environmentObject(appCore)
        case .editHoliday(let existing):
            HolidayEditSheet(
                existing: existing,
                onSave: { saveHoliday($0) },
                onDelete: existing.map { hol in { deleteHoliday(hol.id) } }
            )
        }
    }

    // MARK: - 1. Company Work Hours

    private var companyWorkHoursSection: some View {
        Section {
            DatePicker("Default Start Time", selection: $workDayStart, displayedComponents: .hourAndMinute)
            DatePicker("Default End Time", selection: $workDayEnd, displayedComponents: .hourAndMinute)

            // Work days checkboxes
            VStack(alignment: .leading, spacing: 8) {
                Text("Work Days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(zip(dayOrder, dayLabels)), id: \.0) { day, label in
                        Button {
                            if workDays.contains(day) {
                                workDays.remove(day)
                            } else {
                                workDays.insert(day)
                            }
                        } label: {
                            Text(label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 32, height: 32)
                                .background(workDays.contains(day) ? Color.blue : Color.secondary.opacity(0.15))
                                .foregroundStyle(workDays.contains(day) ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(label) \(workDays.contains(day) ? "selected" : "not selected")")
                    }
                }
            }
            .padding(.vertical, 4)

            Picker("Lunch Break", selection: $lunchDuration) {
                Text("None").tag(0)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("45 min").tag(45)
                Text("60 min").tag(60)
            }

            Toggle("Lunch Paid", isOn: $lunchPaid)

            Picker("Overtime Rule", selection: $overtimeMode) {
                Text("8h/day").tag("daily")
                Text("40h/week").tag("weekly")
            }
            .pickerStyle(.segmented)

            Stepper("OT After: \(overtimeThreshold) hrs", value: $overtimeThreshold, in: 20...60)
        } header: {
            Label("Company Work Hours", systemImage: "clock")
        } footer: {
            Text("Default schedule applied to all employees unless overridden by a shift template.")
        }
    }

    // MARK: - 2. Shift Templates

    private var shiftTemplatesSection: some View {
        Section {
            if shiftTemplates.isEmpty {
                Label("No shift templates defined", systemImage: "tray")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shiftTemplates) { template in
                    Button {
                        activeSheet = .editShiftTemplate(template)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    if let hat = template.hatName {
                                        Text(hat)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                    Text("\(template.startTime)–\(template.endTime)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                activeSheet = .editShiftTemplate(nil)
            } label: {
                Label("Add Shift Template", systemImage: "plus.circle.fill")
            }
        } header: {
            Label("Shift Templates", systemImage: "rectangle.stack")
        } footer: {
            Text("Role-based schedules. Each template can be assigned to a specific job hat (role).")
        }
    }

    // MARK: - 3. Holidays

    private var holidaysSection: some View {
        Section {
            if holidays.isEmpty {
                Label("No holidays defined", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(holidays) { holiday in
                    Button {
                        activeSheet = .editHoliday(holiday)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holiday.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(holiday.date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if holiday.isPaid {
                                        Text("Paid")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.15))
                                            .foregroundStyle(.green)
                                            .clipShape(Capsule())
                                    } else {
                                        Text("Unpaid")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundStyle(.orange)
                                            .clipShape(Capsule())
                                    }
                                    if holiday.isRecurring {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                activeSheet = .editHoliday(nil)
            } label: {
                Label("Add Holiday", systemImage: "plus.circle.fill")
            }
        } header: {
            Label("Holidays", systemImage: "gift")
        }
    }

    // MARK: - 4. Dispatch Rules

    private var dispatchRulesSection: some View {
        Section {
            Stepper("Min Notice: \(minNoticeHours) hours", value: $minNoticeHours, in: 0...72, step: 4)
            Stepper("Max Hours/Day: \(maxHoursPerDay)h", value: $maxHoursPerDay, in: 6...16)
            Toggle("Require Manager Approval to Override Overtime", isOn: $requireOvertimeApproval)
        } header: {
            Label("Dispatch Rules", systemImage: "paperplane")
        } footer: {
            Text("Rules that apply when dispatching workers to job sites.")
        }
    }

    // MARK: - 5. Supervisor Settings

    private var supervisorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Supervisor Hats")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(allHats) { hat in
                        Button {
                            if supervisorHatIds.contains(hat.id) {
                                supervisorHatIds.remove(hat.id)
                            } else {
                                supervisorHatIds.insert(hat.id)
                            }
                        } label: {
                            Text(hat.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(supervisorHatIds.contains(hat.id) ? Color.blue : Color.secondary.opacity(0.12))
                                .foregroundStyle(supervisorHatIds.contains(hat.id) ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)

            Toggle("See own team's schedule only", isOn: $supervisorSeeOwnTeamOnly)
            Toggle("Can approve time-off for their team", isOn: $supervisorCanApproveTimeOff)
        } header: {
            Label("Supervisor Settings", systemImage: "person.badge.shield.checkmark")
        } footer: {
            Text("Selected hats will have supervisor privileges on their team.")
        }
    }

    // MARK: - Save

    private var saveSection: some View {
        Section {
            Button {
                saveConfig()
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save Configuration").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(isSaving)
        }
    }

    // MARK: - Save / Load

    private func saveConfig() {
        guard let service = appCore.settingsService else {
            saveError = "Service not available"
            return
        }
        isSaving = true
        saveError = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        do {
            try service.upsertSettingsMap([
                "work_day_start": formatter.string(from: workDayStart),
                "work_day_end": formatter.string(from: workDayEnd),
                "lunch_duration": "\(lunchDuration)",
                "lunch_paid": lunchPaid ? "1" : "0",
                "work_days": workDays.sorted().joined(separator: ","),
                "overtime_mode": overtimeMode,
                "overtime_threshold": "\(overtimeThreshold)",
                "default_break_minutes": "\(defaultBreakMinutes)",
                "weekend_scheduling": enableWeekendScheduling ? "1" : "0",
                "min_notice_hours": "\(minNoticeHours)",
                "max_hours_per_day": "\(maxHoursPerDay)",
                "require_overtime_approval": requireOvertimeApproval ? "1" : "0",
                "supervisor_hat_ids": supervisorHatIds.map(String.init).joined(separator: ","),
                "supervisor_see_own_team": supervisorSeeOwnTeamOnly ? "1" : "0",
                "supervisor_approve_timeoff": supervisorCanApproveTimeOff ? "1" : "0",
            ], category: "scheduling")
            showSaveConfirmation = true
        } catch {
            saveError = userFriendlyError(error, context: "save")
        }
        isSaving = false
    }

    private func loadAll() {
        guard let settings = appCore.settingsService else {
            loadErrorMsg = "Service not available"
            return
        }

        // Load settings
        do {
            let s = try settings.getSettingsByCategory("scheduling")
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"

            if let v = s["work_day_start"], let d = formatter.date(from: v) { workDayStart = d }
            if let v = s["work_day_end"], let d = formatter.date(from: v) { workDayEnd = d }
            if let v = s["lunch_duration"], let n = Int(v) { lunchDuration = n }
            if let v = s["lunch_paid"] { lunchPaid = v == "1" }
            if let v = s["work_days"], !v.isEmpty {
                workDays = Set(v.split(separator: ",").map(String.init))
            }
            if let v = s["overtime_mode"] { overtimeMode = v }
            if let v = s["overtime_threshold"], let n = Int(v) { overtimeThreshold = n }
            if let v = s["default_break_minutes"], let n = Int(v) { defaultBreakMinutes = n }
            if let v = s["weekend_scheduling"] { enableWeekendScheduling = v == "1" }
            if let v = s["min_notice_hours"], let n = Int(v) { minNoticeHours = n }
            if let v = s["max_hours_per_day"], let n = Int(v) { maxHoursPerDay = n }
            if let v = s["require_overtime_approval"] { requireOvertimeApproval = v == "1" }
            if let v = s["supervisor_hat_ids"], !v.isEmpty {
                supervisorHatIds = Set(v.split(separator: ",").compactMap { Int64($0) })
            }
            if let v = s["supervisor_see_own_team"] { supervisorSeeOwnTeamOnly = v == "1" }
            if let v = s["supervisor_approve_timeoff"] { supervisorCanApproveTimeOff = v == "1" }
        } catch {
            loadErrorMsg = userFriendlyError(error, context: "load settings")
        }

        // Load shift templates
        if let svc = appCore.schedulingService {
            shiftTemplates = (try? svc.getShiftTemplates()) ?? []
            holidays = (try? svc.getHolidays()) ?? []
        }

        // Load hats for supervisor picker
        if let people = appCore.peopleService {
            allHats = (try? people.listHats()) ?? []
        }
    }

    // MARK: - Template & Holiday Actions

    private func saveShiftTemplate(_ data: ShiftTemplateEditSheet.TemplateData) {
        guard let svc = appCore.schedulingService else { return }
        do {
            try svc.saveShiftTemplate(
                id: data.existingId, name: data.name, hatId: data.hatId,
                workDays: data.workDays, startTime: data.startTime, endTime: data.endTime,
                breakMinutes: data.breakMinutes, breakPaid: data.breakPaid,
                overtimeRule: data.overtimeRule
            )
            shiftTemplates = (try? svc.getShiftTemplates()) ?? []
        } catch {
            saveError = userFriendlyError(error, context: "save shift template")
        }
        activeSheet = nil
    }

    private func deleteShiftTemplate(_ id: Int64) {
        guard let svc = appCore.schedulingService else { return }
        do {
            try svc.deleteShiftTemplate(id: id)
            shiftTemplates = (try? svc.getShiftTemplates()) ?? []
        } catch {
            saveError = userFriendlyError(error, context: "delete shift template")
        }
        activeSheet = nil
    }

    private func saveHoliday(_ data: HolidayEditSheet.HolidayData) {
        guard let svc = appCore.schedulingService else { return }
        do {
            try svc.saveHoliday(
                id: data.existingId, name: data.name, date: data.date,
                isPaid: data.isPaid, isRecurring: data.isRecurring
            )
            holidays = (try? svc.getHolidays()) ?? []
        } catch {
            saveError = userFriendlyError(error, context: "save holiday")
        }
        activeSheet = nil
    }

    private func deleteHoliday(_ id: Int64) {
        guard let svc = appCore.schedulingService else { return }
        do {
            try svc.deleteHoliday(id: id)
            holidays = (try? svc.getHolidays()) ?? []
        } catch {
            saveError = userFriendlyError(error, context: "delete holiday")
        }
        activeSheet = nil
    }
}

// MARK: - FlowLayout (simple wrapping layout)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, width: proposal.width ?? .infinity)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, placement) in result.placements.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private struct LayoutResult {
        var placements: [(x: CGFloat, y: CGFloat, size: CGSize)] = []
        var size: CGSize = .zero
    }

    private func layout(subviews: Subviews, width: CGFloat) -> LayoutResult {
        var result = LayoutResult()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            result.placements.append((x: x, y: y, size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        result.size = CGSize(width: width, height: y + rowHeight)
        return result
    }
}

// MARK: - Date Helper

private extension Date {
    static func timeOnly(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Shift Template Edit Sheet

struct ShiftTemplateEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct TemplateData {
        var existingId: Int64?
        var name: String
        var hatId: Int64?
        var workDays: String
        var startTime: String
        var endTime: String
        var breakMinutes: Int
        var breakPaid: Bool
        var overtimeRule: String
    }

    let existing: SchedulingService.ShiftTemplateRow?
    let hats: [PeopleService.HatListItem]
    let onSave: (TemplateData) -> Void
    let onDelete: (() -> Void)?

    @State private var name = ""
    @State private var selectedHatId: Int64 = 0
    @State private var selectedDays: Set<String> = ["mon", "tue", "wed", "thu", "fri"]
    @State private var startTime = Date.timeOnly(hour: 7, minute: 0)
    @State private var endTime = Date.timeOnly(hour: 17, minute: 0)
    @State private var breakMinutes = 30
    @State private var breakPaid = false
    @State private var overtimeRule = "company_default"
    @State private var showDeleteConfirm = false

    private let dayOrder = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private let dayLabels = ["M", "T", "W", "Th", "F", "Sa", "Su"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Info") {
                    TextField("Template Name", text: $name)

                    Picker("Job Hat", selection: $selectedHatId) {
                        Text("Any Role").tag(Int64(0))
                        ForEach(hats) { hat in
                            Text(hat.name).tag(hat.id)
                        }
                    }
                }

                Section("Schedule") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Work Days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(Array(zip(dayOrder, dayLabels)), id: \.0) { day, label in
                                Button {
                                    if selectedDays.contains(day) { selectedDays.remove(day) }
                                    else { selectedDays.insert(day) }
                                } label: {
                                    Text(label)
                                        .font(.caption).fontWeight(.semibold)
                                        .frame(width: 32, height: 32)
                                        .background(selectedDays.contains(day) ? Color.blue : Color.secondary.opacity(0.15))
                                        .foregroundStyle(selectedDays.contains(day) ? .white : .primary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section("Breaks") {
                    Picker("Break Duration", selection: $breakMinutes) {
                        Text("None").tag(0)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    Toggle("Break Paid", isOn: $breakPaid)
                }

                Section("Overtime") {
                    Picker("Overtime Rule", selection: $overtimeRule) {
                        Text("Use Company Default").tag("company_default")
                        Text("8h/day").tag("daily_8")
                        Text("10h/day").tag("daily_10")
                        Text("40h/week").tag("weekly_40")
                    }
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Template", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing != nil ? "Edit Template" : "New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { populateFromExisting() }
            .confirmationDialog("Delete this template?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Template", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func populateFromExisting() {
        guard let t = existing else { return }
        name = t.name
        selectedHatId = t.hatId ?? 0
        // Parse work days JSON
        if let data = t.workDays.data(using: .utf8),
           let days = try? JSONDecoder().decode([String].self, from: data) {
            selectedDays = Set(days)
        }
        // Parse times
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if let d = formatter.date(from: t.startTime) { startTime = d }
        if let d = formatter.date(from: t.endTime) { endTime = d }
        breakMinutes = t.breakMinutes
        breakPaid = t.breakPaid
        overtimeRule = t.overtimeRule
    }

    private func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let daysArray = dayOrder.filter { selectedDays.contains($0) }
        let daysJSON = (try? JSONEncoder().encode(daysArray)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        onSave(TemplateData(
            existingId: existing?.id,
            name: name.trimmingCharacters(in: .whitespaces),
            hatId: selectedHatId == 0 ? nil : selectedHatId,
            workDays: daysJSON,
            startTime: formatter.string(from: startTime),
            endTime: formatter.string(from: endTime),
            breakMinutes: breakMinutes,
            breakPaid: breakPaid,
            overtimeRule: overtimeRule
        ))
    }
}

// MARK: - Holiday Edit Sheet

struct HolidayEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct HolidayData {
        var existingId: Int64?
        var name: String
        var date: String
        var isPaid: Bool
        var isRecurring: Bool
    }

    let existing: SchedulingService.HolidayRow?
    let onSave: (HolidayData) -> Void
    let onDelete: (() -> Void)?

    @State private var name = ""
    @State private var selectedDate = Date()
    @State private var isPaid = true
    @State private var isRecurring = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Holiday Info") {
                    TextField("Holiday Name", text: $name)
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                }

                Section("Options") {
                    Toggle("Paid Holiday", isOn: $isPaid)
                    Toggle("Recurring Annually", isOn: $isRecurring)
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Holiday", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing != nil ? "Edit Holiday" : "New Holiday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { populateFromExisting() }
            .confirmationDialog("Delete this holiday?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Holiday", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func populateFromExisting() {
        guard let h = existing else { return }
        name = h.name
        isPaid = h.isPaid
        isRecurring = h.isRecurring
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let d = formatter.date(from: h.date) { selectedDate = d }
    }

    private func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        onSave(HolidayData(
            existingId: existing?.id,
            name: name.trimmingCharacters(in: .whitespaces),
            date: formatter.string(from: selectedDate),
            isPaid: isPaid,
            isRecurring: isRecurring
        ))
    }
}
