# 44D — Contractor Detail Page Rebuild

> **Chain position:** **44D** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets

## Instructions

**IMPORTANT:** Before implementing, read `IOSContractorDetailPage.swift` and `IOSContractorsPage.swift`. Rebuild the detail page with qualifications, job history, rating system, and notes. Fix the showXxx Bool to ActiveSheet on the contractors list page.

## Context

Contractors (subcontractors, GCs) need detailed records for compliance and quality tracking. Subcontractors get full quality scores (reliability, quality, on-time). GCs/general contractors get notes only (no scoring — they're the client, not the worker). Qualifications like license, insurance, W-9, and certifications are optional but important for compliance.

## Task

### Step 1: Fix IOSContractorsPage.swift ActiveSheet

```swift
// BEFORE:
@State private var showCreateContractor = false
// (or similar Bool pattern)

// AFTER:
private enum ActiveSheet: Identifiable {
    case create
    case edit(Contractor)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let c): return "edit-\(c.id ?? 0)"
        }
    }
}
@State private var activeSheet: ActiveSheet?
```

### Step 2: Rebuild IOSContractorDetailPage.swift

```swift
List {
    // Contact Info
    Section {
        LabeledContent("Company", value: contractor.companyName ?? "—")
        LabeledContent("Contact", value: contractor.contactName ?? "—")
        if let phone = contractor.phone {
            LabeledContent("Phone", value: phone)
        }
        if let email = contractor.email {
            LabeledContent("Email", value: email)
        }
        if let address = contractor.address {
            LabeledContent("Address", value: address)
        }
    } header: {
        Text("Contact Info")
    }

    // Qualifications (optional fields)
    Section {
        QualificationRow(label: "License", value: contractor.licenseNumber, expiry: contractor.licenseExpiry)
        QualificationRow(label: "Insurance", value: contractor.insuranceProvider, expiry: contractor.insuranceExpiry)
        QualificationRow(label: "W-9", value: contractor.hasW9 ? "On File" : nil, expiry: nil)
        if !certifications.isEmpty {
            ForEach(certifications) { cert in
                QualificationRow(label: cert.name, value: cert.number, expiry: cert.expiryDate)
            }
        }
    } header: {
        Text("Qualifications")
    } footer: {
        Text("Optional — track licenses and certifications for compliance")
    }

    // Rating (subcontractors only)
    if contractor.contractorType == "subcontractor" {
        Section {
            RatingRow(label: "Quality", value: rating?.qualityScore ?? 0)
            RatingRow(label: "On-Time", value: rating?.onTimeScore ?? 0)
            RatingRow(label: "Reliability", value: rating?.reliabilityScore ?? 0)
            HStack {
                Text("Overall").font(.headline)
                Spacer()
                Text(String(format: "%.1f", rating?.overallScore ?? 0))
                    .font(.headline)
                    .foregroundStyle(ratingColor(rating?.overallScore ?? 0))
                Image(systemName: "star.fill")
                    .foregroundStyle(ratingColor(rating?.overallScore ?? 0))
            }
        } header: {
            Text("Performance Rating")
        }
    }

    // Job History
    Section {
        ForEach(jobHistory) { job in
            HStack {
                VStack(alignment: .leading) {
                    Text(job.name).font(.headline)
                    Text(job.status.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let date = job.completedDate {
                    Text(date, style: .date)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    } header: {
        Text("Job History (\(jobHistory.count))")
    }

    // Notes
    Section {
        ForEach(notes) { note in
            VStack(alignment: .leading, spacing: 2) {
                Text(note.content)
                HStack {
                    Text(note.createdBy)
                    Text("•")
                    Text(note.createdAt, style: .relative)
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        Button { activeSheet = .addNote } label: {
            Label("Add Note", systemImage: "square.and.pencil")
        }
    } header: {
        Text("Notes")
    }
}

struct QualificationRow: View {
    let label: String
    let value: String?
    let expiry: Date?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let val = value {
                Text(val).foregroundStyle(.secondary)
                if let exp = expiry {
                    Text(exp, style: .date)
                        .font(.caption)
                        .foregroundStyle(exp < Date() ? .red : .green)
                }
            } else {
                Text("Not provided")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct RatingRow: View {
    let label: String
    let value: Double  // 0-5

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= Int(value.rounded()) ? "star.fill" : "star")
                    .foregroundStyle(star <= Int(value.rounded()) ? .yellow : .gray)
                    .font(.caption)
            }
            Text(String(format: "%.1f", value))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

### Step 3: Service Methods

```swift
// In PeopleService:
struct ContractorRating: Sendable {
    let qualityScore: Double
    let onTimeScore: Double
    let reliabilityScore: Double
    var overallScore: Double { (qualityScore + onTimeScore + reliabilityScore) / 3.0 }
}

func getContractorRating(contractorId: Int64) async throws -> ContractorRating?
func getContractorJobHistory(contractorId: Int64) async throws -> [JobSummary]
func getContractorCertifications(contractorId: Int64) async throws -> [Certification]
func addContractorNote(contractorId: Int64, content: String, createdBy: Int64) async throws
func getContractorNotes(contractorId: Int64) async throws -> [CommunicationEntry]
```

## Important Notes
- Subcontractors: full rating scores (quality/on-time/reliability)
- GCs/general contractors: notes section only, NO scoring (they're clients)
- Qualifications are optional — many contractors won't have all fields
- Expired qualifications show in RED
- Rating is calculated from actual job data (see 17C supplier scores pattern)
- The contractor type determines which sections appear

## Success Criteria
- [ ] IOSContractorsPage.swift: showXxx Bool → ActiveSheet enum
- [ ] Contact info section with all fields
- [ ] Qualifications section (license, insurance, W-9, certifications)
- [ ] Rating section for subcontractors only (quality, on-time, reliability)
- [ ] GCs get notes section but NO rating
- [ ] Job history with dates
- [ ] Notes section with add note
- [ ] Expired qualifications shown in red
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 44D Results (YYYY-MM-DD)
- IOSContractorsPage: ActiveSheet conversion
- IOSContractorDetailPage: rebuilt with X sections
- PeopleService: X contractor detail methods
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
