# 38B — Break/Lunch UI: Clock Page + Settings + Clock-Out Questions

> **Chain position:** 38A → **38B**
> **Prerequisite:** 38A (break tables + service methods exist)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Task

### Clock Page — Break/Lunch/Supply Run Buttons
When clocked in, show below the clock-out button:

**Break button:**
- Status changes to "On Break" (PAID, still on clock)
- Timer counts from daily break budget
- Notification at timer end
- Auto-ends at budget limit

**Lunch button:**
- First X minutes: PAID (status = lunch_paid)
- After paid portion: prompt "Continue unpaid?"
- Unpaid portion: CLOCKED OUT
- Timer with notification

**Supply Run button:**
- Stays clocked in (NOT a clock-out)
- Activity status changes to "supply_run"
- Manual start/stop OR geofence detection
- Confirmation for geofence triggers

### Break Settings Page
6-section form in Office/Settings:
1. State Required Paid (from break_policies, read-only)
2. State Required Offered Unpaid (read-only)
3. Company Extra Paid (editable)
4. Company Extra Offered (editable)
5. Bonuses (optional, per area: lunch + breaks)
6. Full Breakdown (combined view of all tiers)

State picker at top loads presets.
[Update Data] refreshes from stored labor law data.
[Manual Edit] for custom overrides.

### Clock-Out Questionnaire Addition
Add break verification to the clock-out flow:
- "Did you take your breaks today?" [Yes, all] [I forgot/didn't] [Partial]
- If forgot/partial: which did you miss? [Morning break] [Lunch] [Afternoon break]
- Missed breaks → report sent to Office for handling
- If "yes, all taken" but no break buttons were hit → auto-fill break records at default times

### Bonus Tracking
- If employee sticks to state-minimum breaks (doesn't use company extras):
  - Eligible for configured bonus
  - Tracked per day
  - Only if break buttons used (not auto-filled) → actual verification that user took state-level breaks
  - If questionnaire has to ask → bonus NOT earned (didn't use buttons properly)

## Success Criteria
- [ ] Break/Lunch/Supply Run buttons on Clock page when clocked in
- [ ] Break = paid status change. Lunch = paid then optional unpaid. Supply Run = stays clocked in.
- [ ] Timer with notifications for breaks/lunch
- [ ] Break settings page with 6-section form
- [ ] State preset picker
- [ ] Clock-out questionnaire asks about missed breaks
- [ ] Auto-fill break records for compliance
- [ ] Bonus tracking for state-minimum adherence
- [ ] Project builds with no errors
