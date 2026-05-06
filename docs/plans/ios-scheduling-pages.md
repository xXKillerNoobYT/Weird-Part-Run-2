# iOS Scheduling Pages — Design Plan

## What This Does

The Scheduling area orchestrates *who is going where and when* — calendar visualization (per-employee + per-job), dispatch board (drag-drop assignment of workers to jobs), shift templates (recurring weekly patterns), time-off requests (with approval chain), flex pool (cross-shop worker availability), weekly availability tracking, sub-scheduling (custom templates), job estimation questionnaires, weekly + end-of-job AI reviews, and capacity planning. Backed by `SchedulingService.swift` (36 public methods, 2096 lines) + 15 iOS pages. Per memory: **highest test breadth in the project (4.1× ratio = 154 tests / 36 methods).**

## Why

Field operations break without disciplined scheduling: workers get double-booked, jobs sit idle waiting for unavailable workers, time-off conflicts erupt week-of, dispatch becomes a daily firefight. The Scheduling area exists to make these decisions explicit and visible: dispatchers see the whole shop's commitments at-a-glance; workers see their week before it starts; managers see capacity vs. demand for next month. The flex pool extends this across multi-shop networks. AI dispatch suggestions (Phase 12) will eventually automate the routine assignments freeing dispatchers to handle exceptions. Weekly/end-of-job review questions feed the daily-report and Q&A escalation systems. Scheduling is also one of the highest-stakes areas for data correctness — a bad availability lookup leads to a missed customer appointment which leads to lost revenue and angry customers. The 4.1× test breadth ratio reflects this: every method is well-tested precisely because the cost of bugs is high.

> **Purpose:** Comprehensive design decisions for all Scheduling-related pages in the iOS app. Covers calendar, dispatch, pipelines (short-term + long-term), AI dispatch, flex pool, capacity planning, job estimation, weekly/end-of-job reviews, and the AI Smart Question System.
>
> **Source:** Design conversation 2026-03-23. Implements pages in `Weird Parts IOS/Features/Scheduling/`.
>
> **Files:** `IOSScheduleCalendarPage`, `IOSDispatchPage`, `IOSTimeOffPage`, `IOSWeeklyAvailabilityPage`, `IOSSubSchedulePage`, `IOSDispatchTemplatesPage`, `IOSTemplateBuilderSheet`, `CreateScheduleEntrySheet`, `CreateDispatchSheet`, `RequestTimeOffSheet`

---

## 1. Calendar (`IOSScheduleCalendarPage`)

### Views

| View | Description |
|------|-------------|
| **Week View** | 7-day horizontal layout with time slots. Primary working view. |
| **Month View** | Traditional month grid with event dots. For overview and date picking. |

### Half-Day Support

- Events can be scheduled as half-day (AM or PM)
- AM = start of day to lunch break
- PM = lunch break to end of day
- Visual: half-day events take up half the vertical space of a full-day event
- Useful for: split assignments, half-day time-off, partial availability

### Calendar Contents

- Job assignments (color-coded by job)
- Time-off (gray overlay)
- Holidays (company-defined)
- Certifications expiring (warning badge)
- Dispatch assignments (linked to dispatch board)

---

## 2. Dispatch Page (`IOSDispatchPage`)

### Gantt-Style Board

The dispatch page is a **drag-and-drop Gantt-style board** showing jobs across a timeline with worker assignments.

```
+--------------------------------------------------+
| < March 17-21, 2026 >              [Week|Month]  |
+--------------------------------------------------+
|           | Mon  | Tue  | Wed  | Thu  | Fri     |
+--------------------------------------------------+
| Job #123  | [Alpha Crew - Rough-In     ]          |
| Kitchen   |                                       |
|           |                                       |
| Job #456  |        [Beta Crew - Trim   ]          |
| Bathroom  |                                       |
|           |                                       |
| Job #789  | [Service - AM]                        |
| Service   |                                       |
+--------------------------------------------------+
```

### Drag-and-Drop

- Drag a job bar to extend/shorten duration
- Drag a crew assignment to a different job
- Drag to move a job to different dates
- Drop zone highlights valid positions

### Job Information Shown

| Element | Description |
|---------|-------------|
| **Job name** | Job title/number |
| **Current stage** | What stage the job is in (Rough-In, Trim, etc.) |
| **Crew assigned** | Which team/workers are on this job |
| **Duration bar** | Visual length showing scheduled duration |
| **Color** | Color-coded by job type or status |

### Crew History (3 months)

- When assigning a crew to a job, show their last 3 months of assignments
- Helps dispatcher see patterns, avoid burnout, maintain variety
- Displayed as a mini-timeline below the crew selector

### Crew Continuity Tracking

- System tracks how long a crew has been on the same job
- Alert when crew has been on one job for an extended period
- Helps ensure cross-training and prevent single-point-of-knowledge risks

### Time-Off Conflict Popup

- When dragging a worker/crew to a date, if anyone has time-off:
  - Popup shows: "[Name] has time-off on [Date]. Assign anyway?"
  - Options: Assign (override), Cancel, Find Alternative
  - "Find Alternative" suggests available workers with similar skills

---

## 3. Short-Term Pipeline Page

The Short-Term Pipeline shows jobs that need to be scheduled soon, organized by urgency.

### Sections

| Section | Target Count | Description |
|---------|-------------|-------------|
| **Start Anytime** | Target: 3+ | Jobs ready to start, all prerequisites met |
| **Schedule Needed** | Target: 2+ | Jobs that need a start date assigned |
| **Favorite GC** | Target: 1+ | Jobs from preferred GCs (priority scheduling) |
| **Small Jobs** | Pool | Quick jobs that can fill gaps in the schedule |

### Target Counts

Each section has a target minimum. When below target, the section header shows a warning badge. This helps the dispatcher maintain a healthy pipeline.

### Job Cards in Pipeline

Each job card shows:
- Job name and customer
- Estimated duration
- Required skills/certifications
- Priority level
- How long it's been waiting (days since created/approved)

---

## 4. Long-Term Pipeline Page

The Long-Term Pipeline provides a **3-year timeline view** for strategic planning.

### 3-Year Timeline View

```
+--------------------------------------------------+
|  2026        |  2027        |  2028              |
+--------------------------------------------------+
| Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec   |
| [========]                                        |
|     [============]                                |
|              [====]                               |
|                        [================]         |
+--------------------------------------------------+
| Capacity: [===========-------] 72%               |
+--------------------------------------------------+
```

### Capacity Bars by Month

- Each month shows a capacity utilization bar
- Calculated from: scheduled jobs + estimated durations vs available work-days
- Color: green (<80%), yellow (80-95%), red (>95%)
- Helps identify over/under-scheduled months

### Callback Tracking

- Track customers who requested callbacks at specific future dates
- "Call back in 6 months" → appears on pipeline at the right date
- Callback cards show: customer name, reason, original conversation date

### Bid Tracking (Simple)

- Simple bid tracking — not a full estimating system
- Fields: customer, job description, estimated value, bid date, follow-up date, status (Pending, Won, Lost, Expired)
- Won bids convert to jobs
- Lost bids tracked for win-rate analytics

---

## 5. AI Dispatch Suggestions

When the dispatcher needs to assign a crew to a job, AI provides 3 options with reasoning.

### How It Works

1. Dispatcher selects a job that needs assignment
2. Taps "AI Suggest" button
3. AI analyzes: worker skills, certifications, availability, location, crew history, job requirements
4. Returns 3 ranked options

### Suggestion Format

```
+--------------------------------------------------+
| OPTION 1: Alpha Crew (85 points)                  |
| +20 pts: All required certs                       |
| +25 pts: 3 similar jobs completed                 |
| +15 pts: Currently in area                        |
| +10 pts: Available all week                       |
| +15 pts: Customer preference match                |
| -0 pts: No conflicts                              |
+--------------------------------------------------+

| OPTION 2: Beta Crew (72 points)                   |
| +20 pts: All required certs                       |
| +15 pts: 1 similar job completed                  |
| +12 pts: Available Mon-Wed only                   |
| +10 pts: Good reliability rating                  |
| +15 pts: Shortest commute                         |
| -0 pts: No conflicts                              |
+--------------------------------------------------+

| OPTION 3: Mixed Crew (65 points)                  |
| +20 pts: All required certs (combined)            |
| +10 pts: Some similar experience                  |
| +10 pts: All available                            |
| +5 pts: Cross-training opportunity                |
| +20 pts: Cost optimization                        |
| -0 pts: No conflicts                              |
+--------------------------------------------------+
```

### Points-Based Reasoning

Each suggestion shows a point breakdown so the dispatcher understands WHY the AI recommends it. Categories:
- Certifications match
- Experience with similar jobs
- Availability
- Location/commute
- Customer preference
- Cost
- Crew continuity
- Cross-training value

### Dedicated AI Chat for Modifications

After seeing suggestions, the dispatcher can chat with AI:
- "What if I add Mike to Option 2?"
- "Show me options without the Alpha crew"
- "Who's available if I push this to next week?"
- AI recalculates and presents modified options

### Learning from Picks

- AI tracks which options dispatchers choose
- Over time, weighs factors that align with dispatcher preferences
- "You usually prefer crew continuity over shortest commute" — adapts scoring weights

---

## 6. Flex Pool

Jobs that workers can self-assign to, without waiting for dispatch.

### Two Types

| Type | Description |
|------|-------------|
| **Ready to Start** | All prerequisites met, can begin work immediately |
| **Needs Contact** | Customer contact needed before work can begin |

### Rules — Updated by PE-003 Q&A (2026-04-04)

- Flex pool is hat-gated: `self_assign_flex` hat required
- **Location: dedicated tab on the Scheduling page** (NOT Dashboard — keeps everything in one place)
- Workers see ALL flex pool jobs available to them (manager pre-filters by team/person when adding to pool — app doesn't re-filter by worker skills)
- **Who can add to flex pool:** Managers only. They filter by team or person when publishing a job to the pool.
- Tapping "Claim" → confirmation dialog ("Are you sure?") → sets worker as job lead → navigates to Job Detail page
- Once claimed, job becomes active; `assigned_user_id` is set to the claiming worker; `is_flex_pool` cleared
- **Optional: company setting `require_manager_approval_for_flex_claim`** — if enabled, claim shows "Pending Approval" state until manager confirms
- After a claim, manager can reassign, put on hold, or cancel (with proper `manage_dispatch` hat)
- Manager can pull flex job back out of pool before claiming (resets `is_flex_pool = 0`)
- **Dispatch entry:** Claiming writes the worker as job lead; a `dispatch_entries` row is created linking worker to job

### DB Changes Required (before Xcode prompt)

1. Migration: `ALTER TABLE jobs ADD COLUMN is_flex_pool INTEGER NOT NULL DEFAULT 0`
2. `SchedulingService.fetchFlexPool()` — `SELECT * FROM jobs WHERE is_flex_pool = 1 AND status = 'open'` filtered to the pools the user's team is in
3. `SchedulingService.markJobAsFlexPool(jobId:teams:[])` — sets `is_flex_pool = 1`, optionally filters visible teams
4. `SchedulingService.claimFlexJob(jobId:userId:)` — sets lead worker, clears `is_flex_pool`, writes dispatch_entries row
5. Company setting: `flex_claim_requires_approval` boolean in settings

### Flex Pool Card

```
+--------------------------------------------------+
| [Ready] Service Call - 123 Oak St        [Claim]  |
| Customer: Smith · Est: 2-4 hrs                    |
| Skills needed: Journeyman                         |
+--------------------------------------------------+
```

---

## 7. Capacity Planning

### Work-Days (Person-Days)

Capacity is measured in **work-days** (also called person-days), not hours.

- 1 work-day = 1 person working 1 full day
- A crew of 4 for 5 days = 20 work-days
- Capacity is based on **historical job averages**, not estimates

### Why Historical, Not Estimates

- Estimates are unreliable (especially early on)
- Historical data from similar jobs gives better predictions
- System learns: "Residential rough-in typically takes 12 work-days" from completed jobs
- New job types without history fall back to manual estimates

### Capacity Calculation

```
Available work-days = (number of workers) x (working days in period) - (time-off days)
Scheduled work-days = sum of (assigned worker-days for all scheduled jobs)
Utilization = Scheduled / Available x 100%
```

---

## 8. Job Estimation Questionnaire

When a new job comes in, the system presents a questionnaire to gather estimation data.

### Questionnaire Design

- **Grouped questions** by category (Scope, Site Conditions, Customer, Timeline)
- **Stage-aware:** Different questions for different job types and stages
- **"?" for unknowns:** User can mark any question as unknown/TBD — logged for follow-up
- Unknown answers don't block job creation, but trigger reminders

### Example Questions

| Category | Question | Answer Type |
|----------|----------|-------------|
| Scope | How many circuits? | Number |
| Scope | Panel upgrade needed? | Yes/No/? |
| Site | New construction or retrofit? | Choice |
| Site | Access restrictions? | Text/? |
| Customer | Repeat customer? | Yes/No |
| Timeline | Preferred start date? | Date/? |
| Timeline | Hard deadline? | Date/? |

### AI Learning

- AI tracks which questions lead to accurate estimates
- After 15+ completed jobs, AI suggests new questions (see Section 10)
- Questions that don't correlate with outcomes get flagged for removal

---

## 9. Reviews

### Weekly Reviews

Scheduled review prompts (configurable frequency) that check:

| Check | Description |
|-------|-------------|
| **Delay factors** | Are any jobs behind schedule? Why? |
| **Unanswered questions** | Any "?" answers from questionnaires still unresolved? |
| **On-track check** | Are jobs progressing as expected? |
| **Resource conflicts** | Any upcoming scheduling conflicts? |
| **Pipeline health** | Are pipeline sections at target levels? |

### End-of-Job Reviews

When a job is marked complete, prompt a review:

| Section | Content |
|---------|---------|
| **Estimate vs Actual** | Compare estimated work-days to actual |
| **Categorized delays** | What caused delays? (materials, weather, change orders, customer, internal) |
| **Crew feedback** | How did the crew perform? Any notes? |
| **GC rating** | Rate the GC (if applicable) — for internal tracking |
| **Lessons learned** | Free-text field for what went well / could improve |
| **Question review** | Which estimation questions were most useful? |

End-of-job review data feeds back into:
- Capacity planning (better historical averages)
- AI estimation (better question selection)
- Crew assignment (performance data)

---

## 10. AI Smart Question System

After the company completes 15+ jobs, the AI begins suggesting improvements to the estimation questionnaire.

### How It Works

1. **Analysis:** AI analyzes completed jobs — compares questionnaire answers to actual outcomes (duration, cost, delays)
2. **Correlation:** Identifies which questions most strongly predict outcomes
3. **Suggestion:** Proposes new questions that could improve accuracy

### Suggestion Types

| Type | Description |
|------|-------------|
| **New question** | AI suggests a question that doesn't exist yet, based on patterns in job data |
| **Stage-specific** | AI suggests adding a question to a specific stage's questionnaire |
| **Job-specific** | Based on GC history, area, or job type — "Jobs for [GC Name] usually need [X], ask about it" |
| **Remove question** | AI suggests a question that never correlates with outcomes |

### Rejected Questions Log

- When a user rejects an AI-suggested question, it's logged with the reason
- AI periodically reconsiders rejected questions (every 6 months)
- If circumstances change (new job types, new patterns), AI can re-suggest a previously rejected question
- Re-suggestion includes: "Previously rejected on [date] because [reason]. New evidence: [explanation]."

### Stage-Specific Questions

- Questions can be assigned to specific job stages
- Example: "Rough-in" stage might have questions about wire routing that don't apply to "Trim"
- AI learns which questions matter at which stages from historical data

### History-Based Suggestions

AI considers job context when suggesting questions:

| Context | Example Suggestion |
|---------|-------------------|
| **GC history** | "Jobs from [GC Name] have had 40% change-order rate. Ask: 'Is scope finalized?'" |
| **Area/location** | "Jobs in [Area] often have permit delays. Ask: 'Permits in hand?'" |
| **Job type** | "Commercial jobs with >50 circuits average 3 extra days. Ask: 'Circuit count confirmed?'" |

---

## 11. Implementation Notes

### Service Layer Requirements

All scheduling operations go through `SchedulingService` in WiredPartCore.

Key service methods:
- `fetchSchedule(dateRange:, view:)` — calendar data
- `fetchDispatchBoard(dateRange:)` — Gantt-style dispatch data
- `assignCrew(jobId:, crewId:, dateRange:)` — crew assignment
- `fetchFlexPool()` — available flex pool jobs
- `claimFlexJob(jobId:)` — self-assign from flex pool
- `fetchPipeline(type:)` — short-term or long-term pipeline
- `generateAIDispatchSuggestions(jobId:)` — AI crew suggestions
- `fetchCapacity(dateRange:)` — capacity utilization data
- `fetchEstimationQuestionnaire(jobType:)` — job estimation questions
- `submitJobReview(jobId:, review:)` — end-of-job review
- `fetchAISuggestedQuestions()` — AI question suggestions
- `respondToSuggestion(id:, action:, reason:)` — accept/reject AI suggestion

### Hat Permissions for Scheduling

| Hat | What It Controls |
|-----|-----------------|
| `manage_dispatch` | Create/edit dispatch assignments |
| `view_dispatch` | View dispatch board (read-only) |
| `manage_schedule` | Edit calendar entries |
| `approve_time_off` | Approve/deny time-off requests |
| `self_assign_flex` | Claim jobs from flex pool |
| `manage_pipeline` | Edit pipeline entries, bid tracking |
| `manage_templates` | Create/edit dispatch templates |
| `view_capacity` | View capacity planning data |

---

---

## 12. Unplanned Files (Documented for Record)

### `IOSScheduleConfigPage`

Added during implementation (not in original plan). A settings/configuration page for scheduling globals:
- Work day start/end times (24hr format)
- Lunch and break duration defaults
- Overtime threshold (default 40 hrs/week)
- Weekend scheduling toggle

**Note:** Overlaps with Settings → Operations (prompt 52B). Could be moved under Settings or kept under Scheduling navigation. No action required — functionality is appropriate and correctly implemented via SettingsService.

---

*Last updated: 2026-03-23 (plan-enforcer audit: 2026-03-29)*
