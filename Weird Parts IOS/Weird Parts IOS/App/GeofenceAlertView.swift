import SwiftUI
import CoreLocation
import WiredPartCore

/// Full-screen modal shown when worker leaves the 1-mile radius of their clocked-in job.
/// Blocks all other app interaction until the worker responds.
struct GeofenceAlertView: View {
    @EnvironmentObject private var appCore: AppCore
    @ObservedObject var geofenceManager: GeofenceManager

    let onResolved: () -> Void

    @State private var selectedReason: ExitReason?
    @State private var otherNotes = ""
    @State private var targetJobId: Int64?
    @State private var activeJobs: [JobOption] = []
    @State private var isProcessing = false
    @State private var loadError: String?
    @State private var errorMessage: String?
    @State private var showError = false

    private var currentJobName: String {
        geofenceManager.currentJobName ?? "Unknown Job"
    }

    private var currentJobId: Int64 {
        geofenceManager.currentJobId ?? 0
    }

    enum ExitReason: String, CaseIterable {
        case supplyRun = "Supply Run"
        case anotherJob = "Going to Another Job"
        case lunch = "Lunch Break"
        case breakTime = "Break"
        case doneForDay = "Done for the Day"
        case other = "Other"
    }

    struct JobOption: Identifiable {
        let id: Int64
        let name: String
        let number: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Warning header
                    VStack(spacing: 12) {
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("You've Left the Job Area")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("You're clocked in to **\(currentJobName)** but you've moved outside the job site. What happened?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let exitTime = geofenceManager.exitTime {
                            Text("Detected at \(exitTime.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 32)

                    // Reason buttons
                    VStack(spacing: 12) {
                        ForEach(ExitReason.allCases, id: \.rawValue) { reason in
                            Button {
                                selectedReason = reason
                                if reason == .anotherJob { loadActiveJobs() }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: iconFor(reason))
                                        .font(.title3)
                                        .frame(width: 28)
                                        .foregroundStyle(colorFor(reason))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reason.rawValue)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Text(descriptionFor(reason))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if selectedReason == reason {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedReason == reason
                                            ? Color.blue.opacity(0.08)
                                            : Color(.secondarySystemGroupedBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedReason == reason ? Color.blue.opacity(0.3) : .clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Job picker (if "Another Job" selected)
                    if selectedReason == .anotherJob && !activeJobs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Which job are you going to?")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ForEach(activeJobs) { job in
                                Button {
                                    targetJobId = job.id
                                } label: {
                                    HStack {
                                        Text(job.name)
                                            .font(.subheadline)
                                        if !job.number.isEmpty {
                                            Text("#\(job.number)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if targetJobId == job.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(targetJobId == job.id
                                                ? Color.blue.opacity(0.06)
                                                : Color(.tertiarySystemGroupedBackground))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Load error display
                    if let loadError, selectedReason == .anotherJob {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(loadError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Notes (if "Other" selected)
                    if selectedReason == .other {
                        TextField("What happened?", text: $otherNotes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .padding(.horizontal, 20)
                    }

                    // Confirm button
                    Button {
                        Task { await handleResponse() }
                    } label: {
                        if isProcessing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Confirm")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedReason == nil || isProcessing ||
                              (selectedReason == .anotherJob && targetJobId == nil) ||
                              (selectedReason == .other && otherNotes.trimmingCharacters(in: .whitespaces).isEmpty))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .interactiveDismissDisabled(true)
            .navigationTitle("Location Alert")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Handle Response

    private func handleResponse() async {
        guard let reason = selectedReason else { return }
        isProcessing = true

        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else {
            await MainActor.run {
                errorMessage = "App services not available. Please restart the app."
                showError = true
                isProcessing = false
            }
            return
        }

        // Get active labor entry for clock-out
        let activeEntryId: Int64?
        do {
            let entry = try service.getActiveClockEntry(userId: userId)
            activeEntryId = entry?.id
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "load clock entry")
                showError = true
                isProcessing = false
            }
            return
        }

        let exitLat = geofenceManager.exitLocation?.latitude
        let exitLng = geofenceManager.exitLocation?.longitude

        do {
            switch reason {
            case .supplyRun:
                // Stay clocked in, acknowledge and continue
                break

            case .anotherJob:
                if let newJobId = targetJobId, let entryId = activeEntryId {
                    try service.clockOut(laborEntryId: entryId, gpsLat: exitLat, gpsLng: exitLng)
                    try service.clockIn(userId: userId, jobId: newJobId, gpsLat: exitLat, gpsLng: exitLng)
                }

            case .lunch, .breakTime, .doneForDay:
                if let entryId = activeEntryId {
                    try service.clockOut(laborEntryId: entryId, gpsLat: exitLat, gpsLng: exitLng)
                }

            case .other:
                // Stay clocked in, acknowledge with notes
                break
            }

            await MainActor.run {
                geofenceManager.acknowledgeExit()
                isProcessing = false
                onResolved()
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "process response")
                showError = true
                isProcessing = false
            }
        }
    }

    // MARK: - Load Jobs

    private func loadActiveJobs() {
        guard let service = appCore.jobsService else {
            loadError = "Jobs service not available."
            return
        }
        do {
            let jobs = try service.listActiveJobs(excludingJobId: currentJobId)
            activeJobs = jobs.map { job in
                JobOption(id: job.id, name: job.jobName, number: job.jobNumber)
            }
            loadError = nil
        } catch {
            loadError = userFriendlyError(error, context: "load jobs")
        }
    }

    // MARK: - Helpers

    private func iconFor(_ reason: ExitReason) -> String {
        switch reason {
        case .supplyRun: return "truck.box.fill"
        case .anotherJob: return "arrow.right.circle.fill"
        case .lunch: return "fork.knife"
        case .breakTime: return "cup.and.saucer.fill"
        case .doneForDay: return "moon.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    private func colorFor(_ reason: ExitReason) -> Color {
        switch reason {
        case .supplyRun: return .blue
        case .anotherJob: return .orange
        case .lunch: return .green
        case .breakTime: return .purple
        case .doneForDay: return .indigo
        case .other: return .gray
        }
    }

    private func descriptionFor(_ reason: ExitReason) -> String {
        switch reason {
        case .supplyRun: return "Getting supplies. Clock keeps running."
        case .anotherJob: return "Clock out here, clock in at the new job."
        case .lunch: return "Clock out for lunch."
        case .breakTime: return "Taking a break. Clock pauses."
        case .doneForDay: return "Clock out and done."
        case .other: return "Something else — explain below."
        }
    }
}
