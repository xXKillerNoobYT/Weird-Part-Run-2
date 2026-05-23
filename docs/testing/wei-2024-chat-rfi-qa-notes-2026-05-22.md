# WEI-2024 Chat/RFI QA Notes

Date: 2026-05-22 MDT
Issue: WEI-2024
Related GitHub issue: #553

## Automated coverage added

- `BadgeCountServiceTests.testUnreadMessagesRequiresActiveChannelMembership`
  - Verifies the Chat tab unread badge does not count messages from channels where the current user has no active `chat_channel_members` row.
- `BadgeCountServiceTests.testUnreadMessagesRequiresNonRemovedMembership`
  - Verifies the Chat tab unread badge ignores channels where the current user's membership has `left_at` set.
- `ChatServiceTests.testListSupplierChannelsRequiresActiveMembership`
  - Verifies supplier-channel lists hide channels after a user's channel membership is removed.
- `ChatServiceTests.testListSupplierChannelsForJobRequiresActiveMembership`
  - Verifies job-linked supplier channels do not leak private channel rows or unread counts to non-members while remaining visible to active members.

## Manual UI walkthrough checklist

These flows still need device/simulator walkthrough evidence because the SwiftUI navigation, badges, attachment pickers, and escalation affordances are UI-level behavior:

1. Channel membership + unread badges
   - Sign in as a user who is not a member of a private/supplier channel.
   - Confirm the Chat tab badge and `IOSChannelsPage` do not include that channel's unread activity.
   - Add the user as a member and confirm the channel appears.
   - Remove/leave the membership and confirm the channel and unread count disappear after refresh.

2. Channel/thread page
   - Open an allowed channel from `IOSChannelsPage`.
   - Confirm message thread load marks read and the channel badge drops after returning to the list.
   - Confirm a disallowed channel cannot be reached via stale navigation/deep link if such a link exists in the UI.

3. Attachments/reference picker
   - From an allowed channel/thread, attach or reference a job/supplier/PO item using the picker.
   - Confirm the item appears in the composed message and persists after reload.
   - Confirm no picker path exposes restricted channels to a non-member.

4. Q&A/RFI walkthrough
   - Create a Q&A item from `IOSQuestionsPage`.
   - Walk escalation forward/back through `IOSEscalationTimeline`.
   - Resolve/reopen where UI supports it and verify list filters update.
   - Create or view an RFI from `IOSRFIListPage`; verify status chips/transitions shown by the UI match the backend state.

## TODO/FIXME review notes

Chat-page TODO markers found during WEI-2024 review are due-date fallback comments in timeline color handling:

- `IOSRFIListPage.swift`
- `IOSQuestionsPage.swift`
- `IOSEscalationTimeline.swift`

They are not dead actions in the chat/RFI flow. They should remain until `QAThreadRow` / RFI rows gain due-date fields, then be converted to `TimelinePriorityColor.color(priority:dueDateString:)`.
