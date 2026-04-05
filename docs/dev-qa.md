# WiredPart Q&A — Requirements & Design Questions

> **Purpose:** Before building any feature, questions are generated here for the owner to answer.
> Questions are organized by feature/change with role-based perspectives.
> **Auto-maintained by:** dev-pipeline-manager scheduled task

---

## How This Works

1. When a new plan is added or a GitHub issue is filed, questions appear here
2. Each question includes context about the current build and proposed changes
3. Questions are tagged by role perspective: Owner, Manager, Employee, Developer, User
4. Answer the questions by editing this file (write answers below each question)
5. Once answered, the dev-pipeline-manager integrates answers into the plan and **removes the question from this file**
6. Unanswered questions block the feature from being auto-built
7. **This file only contains unanswered/unprocessed questions.** Once processed, they're gone — design decisions live in `docs/plans/`.

---

## Pending Questions

---

### DIS-005 — Company PII in UserDefaults During Setup Wizard

**Source:** `docs/DevTODO/DIS-005-userdefaults-pii-wizard.md`
**Current State:** `CompanySetupWizard.swift` (lines 715-720) stores company name, address, phone, email in `UserDefaults` as wizard draft state. `UserDefaults` is unencrypted and readable on unencrypted device backups.
**Proposed Change:** Verify cleanup happens on wizard completion, or migrate wizard state to SQLite (which benefits from iOS Data Protection).
**Affected Modules:** Auth / Settings

#### Questions:

1. **As the Owner:** Are the `UserDefaults` keys (`companySetup_name`, `companySetup_address`, etc.) deleted after the wizard completes successfully? If yes, this is acceptable (temporary storage only). If not, this is a security issue that should be fixed.
   > Answer: No — they are NOT deleted. Confirmed by code audit: no `removeObject` calls exist for any `companySetup_` keys. All 8 keys (including 4 PII keys) persist in the unencrypted plist indefinitely after wizard completion. This is a security issue.

2. **As a Developer:** If wizard state does persist after completion, should we: (A) call `UserDefaults.standard.removeObject(forKey:)` for all 4 keys when wizard saves to DB, or (B) rewrite to store draft state in a `company_setup_draft` SQLite table that gets deleted after completion?
   > Answer: Option B — migrate wizard draft state to a `company_setup_draft` SQLite table. SQLite benefits from iOS Data Protection (encryption at rest). Delete the draft row after wizard completion. This eliminates PII from the unencrypted UserDefaults plist entirely.

---

## Question Template

When generating questions, use this format:

```
### [Feature Name] — [Brief Description]
**Plan:** `docs/plans/[file].md`
**Current State:** [What exists now]
**Proposed Change:** [What would change]

#### Questions:

1. **As an Owner:** [Business/ROI question]
   > Answer: _pending_

2. **As a Manager:** [Workflow/oversight question]
   > Answer: _pending_

3. **As an Employee:** [Daily usage question]
   > Answer: _pending_

4. **As a Developer:** [Technical/integration question]
   > Answer: _pending_

5. **As a User:** [UX/experience question]
   > Answer: _pending_
```
