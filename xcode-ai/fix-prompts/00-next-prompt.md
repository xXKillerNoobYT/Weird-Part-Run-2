# Xcode AI — Work Through Prompts One at a Time

## How to Use This

1. Read the next prompt file listed below
2. Implement everything in that prompt
3. Build and verify zero errors
4. Log results in `xcode-ai/prompt-results-log.md`
5. Come back here and move to the next prompt

## IMPORTANT RULES

- **ONE prompt at a time.** Don't skip ahead.
- **Build after each prompt.** Fix any errors before moving on.
- **Don't modify files from future prompts.** Stay focused on the current prompt.
- **If a prompt references a file that doesn't exist,** create it.
- **If a prompt references a service method that doesn't exist,** create it in the appropriate service file.
- **Log your results** after each prompt completes.
- **Read CLAUDE.md first** for project standards and architecture rules.
- **Read the plan file** referenced in the prompt for design context.

## Prompt Order (work top to bottom)

### Tier 0: Critical Fixes (do first)
1. `34A-ui-quality-audit.md`
2. `35A-daily-report-submit-stubs.md`
3. `35B-job-detail-tab-fixes.md`
4. `35C-scheduling-raw-sql.md`
5. `35D-geofence-alert-fix.md`
6. `35E-fleet-grdb-errors.md`
7. `35F-audit-session-id-fix.md`
8. `35G-settings-grdb-removal.md`
9. `35H-companion-grdb-hats-delete.md`
10. `35I-reports-grdb-removal.md`
11. `55A-final-grdb-cleanup.md`
12. `56A-full-end-to-end-audit.md`
13. `57A-final-cleanup-audit.md`

### Tier 1: Feature Infrastructure
14. `36A-floor-plan-migration.md`
15. `36B-floor-plan-editor-ui.md`
16. `36C-floor-plan-navigation.md`
17. `36D-onboarding-wizard.md`
18. `37A-audit-confidence-migration.md`
19. `37B-audit-count-ui.md`
20. `37C-organization-tab.md`
21. `37D-user-ratings-leaderboard.md`
22. `38A-break-lunch-compliance.md`
23. `38B-break-lunch-ui.md`
24. `39A-hats-permission-audit.md`

### Tier 2: Page Redesigns
25. `40A-clock-todo-integration.md`
26. `40B-clock-live-timer.md`
27. `41A-teams-detail-page.md`
28. `42A-chat-unified-inbox.md`
29. `42B-chat-thread-info.md`
30. `42C-chat-attachments.md`
31. `42D-qa-escalation.md`
32. `43A-notebook-structure.md`
33. `43B-notebook-detail-rebuild.md`
34. `43C-notebook-templates.md`
35. `43D-panel-schedule.md`
36. `43E-daily-report-system.md`
37. `44A-people-dashboard.md`
38. `44B-employee-detail-rebuild.md`
39. `44C-customer-detail-full.md`
40. `44D-contractor-detail.md`
41. `44E-contacts-redesign.md`
42. `44F-payment-tracking.md`
43. `45A-jobs-list-redesign.md`
44. `45B-job-detail-dashboard.md`
45. `45C-job-types-status.md`
46. `45D-warranty-todo.md`
47. `46A-scheduling-calendar.md`
48. `46B-dispatch-board.md`
49. `46C-short-term-pipeline.md`
50. `46D-long-term-pipeline.md`
51. `46E-ai-dispatch.md`
52. `46F-job-estimation.md`
53. `47A-tools-dashboard-redesign.md`
54. `47B-tool-detail-rebuild.md`
55. `47C-kit-management.md`
56. `47D-tool-trade.md`
57. `47E-tool-maintenance-types.md`
58. `47F-tool-management-page.md`
59. `48A-my-vehicle-primary.md`
60. `48B-vehicle-detail-tabs.md`
61. `48C-trailer-mini-warehouse.md`
62. `48D-pre-trip-inspection.md`
63. `48E-fleet-dashboard-kpis.md`
64. `49A-reports-categories.md`
65. `49B-reports-export.md`
66. `49C-fleet-warehouse-scheduling-reports.md`
67. `49D-report-builder.md`
68. `50A-office-dashboard.md`
69. `50B-unified-approvals.md`
70. `50C-office-chat-channel.md`
71. `50D-office-router-cleanup.md`
72. `51A-standard-filter-bar.md`

### Tier 3: Settings + System
73. `52A-settings-grouped-navigation.md`
74. `52B-settings-new-operations-pages.md`
75. `52C-settings-new-warehouse-pages.md`
76. `52D-settings-new-template-pages.md`
77. `52E-settings-functional-features.md`
78. `52F-settings-sync-classification.md`
79. `53A-safe-update-system.md`

### Tier 4: Sync + Advanced
80. `54A-bluetooth-sync-activation.md`
81. `54B-sync-conflict-resolution-ui.md`
82. `54C-sync-device-pairing.md`
83. `54D-ai-sync-conflict-resolution.md`

### Tier 5: Polish + Standards
84. `58A-help-buttons-all-pages.md`
85. `60A-standard-date-filter-bar.md`
86. `60B-jpo-cart-builder-wiring.md`
87. `60C-ai-conversation-memory.md`
88. `60D-office-dashboard.md`
89. `60E-job-detail-dashboard.md`
90. `60F-receiving-back-confirmation.md`
91. `60G-help-buttons-visible.md`
92. `60H-first-launch-checklist.md`
93. `60I-silent-guard-bulk-fix.md`
94. `60J-submit-to-supplier-rename.md`
95. `60K-stock-human-names.md`
96. `60L-broken-sidebar-routes.md`
97. `60M-ai-page-context-all.md`
98. `60N-ai-help-integration.md`
99. `60O-wishlist-migration.md`
100. `60P-unified-approvals.md`
101. `60Q-dispatch-drag-drop.md`
102. `60R-flex-pool.md`
103. `60S-job-stage-bars.md`
104. `60T-background-task-log.md`

### Tier 6: Final Fixes
105. `61A-priority-colors-timeline.md`
106. `61B-old-chips-to-smart-cards.md`
107. `61C-auto-fill-job-context.md`
108. `61D-touch-targets-44px.md`
109. `61E-dead-buttons-fix.md`
110. `61F-orphaned-pages-wire.md`
111. `61G-placeholder-navlinks.md`
112. `61H-people-dashboard-tab.md`
113. `61I-clock-break-explain.md`
114. `61J-questionnaire-skip-guard.md`
115. `61K-receiving-barcode-scan.md`
116. `61L-receiving-default-expected.md`
117. `62A-refreshable-bulk.md`
118. `62B-searchable-bulk.md`
119. `62C-ai-dispatch-wire.md`
120. `62D-orphan-models-cleanup.md`
121. `62E-table-not-found-fallback.md`
122. `62F-receiving-price-format.md`
123. `62G-po-number-safe.md`
124. `62H-receiving-unrouted-warning.md`
125. `62I-po-line-edit-sheet.md`
126. `62J-notebook-ai-merge.md`
127. `62K-weekly-review.md`
128. `62L-multi-user-audit.md`
129. `62M-jpo-hold-chat.md`
130. `62N-po-job-grouping.md`
131. `62O-po-delivery-timeline.md`
132. `62P-po-receipt-history.md`
133. `62Q-jpo-bulk-hold-fix.md`
134. `62R-location-permission.md`
135. `62S-ai-filter-all-pages.md`
136. `62T-audit-checklist-save.md`

### Tier 7: Final Gate
137. `63A-final-gate.md` ✅ PASSED

### Tier 8: Post-Audit Fixes (NEW — start here)
138. `64C-ui-stability-errors-popups.md` ← **START HERE — fixes errors + stuck popups**
139. `63B-final-9-fixes.md`
140. `64A-guided-onboarding-walkthrough.md`
141. `64B-comprehensive-guided-onboarding.md`
142. `65A-guided-onboarding-walkthrough.md` — comprehensive per-module onboarding with hat filtering + progress tracking
143. `65B-company-setup-wizard.md` — 8-step new company data entry wizard for admins
144. `65C-warehouse-setup-fix.md` — fix broken Steps 2-6 in warehouse onboarding wizard
145. `66A-office-dashboard-dead-buttons.md`
146. `66B-old-chips-to-smart-cards.md`
147. `66C-user-friendly-error-messages.md`
148. `64D-silent-guard-returns.md`
149. `64E-panel-schedule-persist.md`
150. `64F-ai-dispatch-surface.md`
151. `64G-jpo-movement-detail.md`

### Tier 9: Final Verification
152. After all Tier 8 prompts complete, do a full build + run. Verify:
     - Zero loading errors on any page
     - Zero stuck popups anywhere
     - Onboarding wizard walks through every page
     - Warehouse setup wizard is fully functional (all 6 steps do real work)
     - Every button does something when tapped
     - Every sheet dismisses properly
     Then update 63A-final-gate.md status to PASSING with today's date.
     Then wait 10 minutes before checking for new prompts.

## Current Progress

Started: 2026-03-15
Last completed: 64A-guided-onboarding-walkthrough.md ✅ POST-GATE PROMPTS COMPLETE
63B-final-9-fixes.md ✅ (2026-03-26) — 9 audit fixes: QR button, AI dispatch, panel persist, SmartFilterCard ×3, error messages ×165, silent guards, popup audit, dead code, attention items
64A-guided-onboarding-walkthrough.md ✅ (2026-03-26) — 4-part onboarding: interactive checklist, welcome overlay, module tour, first-visit hints
Next: 64C-ui-stability-errors-popups.md (Tier 8, prompt 138)

## To Start

Paste this into Xcode AI:

```
Read xcode-ai/fix-prompts/00-next-prompt.md for the ordered list of prompts. Start with the first uncompleted prompt. Read the prompt file, implement everything it says, build and verify zero errors, log results in xcode-ai/prompt-results-log.md, then move to the next prompt. Work one prompt at a time. Build after each one.
```
