# PE-050 — Employee Detail: Certifications + Skills Tabs

**Filed:** 2026-04-21 (AUTO GO people R4 C11b)
**GitHub:** #77
**Status:** READY (service layer done — commit 4c77bed0)

## What's Needed

Add two new tabs to `IOSEmployeeDetailPage.swift`:

### Certifications Tab
- Fetch: `peopleService.getEmployeeCertifications(userId: employee.id)`
- List each cert: certName, certType badge, issuingAuthority?, certNumber?, expiryDate
- Color-code expiry: red if expired, orange if within 30 days, green otherwise
- Add button (managers only): opens AddCertificationSheet with certType, certName, issuingAuthority, certNumber, issuedDate, expiryDate, notes fields
- Swipe-to-delete: calls `removeCertification(id:)` with confirmation

### Skills Tab
- Fetch: `peopleService.getEmployeeSkills(userId: employee.id)`
- List each skill: skillName, proficiency badge (beginner/intermediate/expert), yearsExperience?
- Add button (managers only): opens AddSkillSheet with skillName, proficiency picker, yearsExperience
- Swipe-to-delete: calls `removeSkill(id:)` with confirmation

## Pattern to Follow
Same tab structure as existing Hats & Teams tabs in the page.
Use `ScrollDismissesKeyboard(.immediately)` + `interactiveDismissDisabled(isDirty)` on add sheets.

## Service Methods Available (commit 4c77bed0)
- `people.addCertification(userId:certType:certName:issuingAuthority:certNumber:issuedDate:expiryDate:notes:)`
- `people.removeCertification(id:)`
- `people.addSkill(userId:skillName:proficiency:yearsExperience:verifiedBy:)`
- `people.removeSkill(id:)`
- `people.getEmployeeCertifications(userId:)`
- `people.getEmployeeSkills(userId:)`
- Also available via `getEmployeeDetail(id:)` — certs + skills now pre-loaded in `.certifications` and `.skills` fields
