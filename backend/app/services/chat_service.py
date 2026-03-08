"""
Chat service — orchestrates messaging, channels, read receipts, mentions.

Sits between the router and the 5 chat repos, adding:
  - Membership validation before send/read
  - Auto-enrollment of job crew into job channels
  - Notification dispatch for messages and @mentions
  - Inbox assembly with unread counts + last message preview
"""

from __future__ import annotations

import logging

import aiosqlite

from app.repositories.chat_repo import (
    ChatChannelRepo,
    ChatMemberRepo,
    ChatMessageRepo,
    ChatMentionRepo,
    ChatReadReceiptRepo,
)
from app.services.notification_service import NotificationService

logger = logging.getLogger(__name__)


class ChatService:
    """Orchestrates chat operations with business logic."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.channel_repo = ChatChannelRepo(db)
        self.member_repo = ChatMemberRepo(db)
        self.message_repo = ChatMessageRepo(db)
        self.read_repo = ChatReadReceiptRepo(db)
        self.mention_repo = ChatMentionRepo(db)
        self.notif_service = NotificationService(db)

    # ── Channels ───────────────────────────────────────────────────

    async def get_or_create_job_channel(
        self, job_id: int, user_id: int
    ) -> dict:
        """Get or create a job channel and auto-enroll crew members.

        When a job channel is first created, we pull all workers from
        job_team_members and job_dispatch to auto-populate the member list.
        """
        channel = await self.channel_repo.get_or_create_job_channel(
            job_id, user_id
        )

        # Auto-add crew members if they aren't already in the channel
        crew_ids = await self._get_job_crew(job_id)
        for crew_id in crew_ids:
            if not await self.member_repo.is_member(channel["id"], crew_id):
                await self.member_repo.add_member(channel["id"], crew_id)

        # Ensure the requesting user is also a member
        if not await self.member_repo.is_member(channel["id"], user_id):
            await self.member_repo.add_member(channel["id"], user_id)

        return channel

    async def create_dm_channel(
        self, user_ids: list[int], created_by: int
    ) -> dict:
        """Create or find existing DM channel between users."""
        return await self.channel_repo.create_dm_channel(user_ids, created_by)

    async def get_inbox(self, user_id: int) -> dict:
        """Assemble the full inbox for a user.

        Returns channels with unread counts, last message preview,
        and global unread/mention stats for the badge.
        """
        channels = await self.channel_repo.get_user_channels(user_id)

        # Build channel response list with last message preview
        channel_list = []
        total_unread = 0
        for ch in channels:
            unread = ch.get("unread_count", 0)
            total_unread += unread

            # Build last message preview if available
            last_message = None
            if ch.get("last_msg_id"):
                last_message = {
                    "id": ch["last_msg_id"],
                    "content": ch.get("last_msg_content"),
                    "message_type": ch.get("last_msg_type", "text"),
                    "sender_name": ch.get("last_msg_sender"),
                    "created_at": ch.get("last_msg_at"),
                }

            channel_list.append({
                "id": ch["id"],
                "channel_type": ch["channel_type"],
                "job_id": ch.get("job_id"),
                "name": ch.get("name"),
                "created_by": ch.get("created_by"),
                "created_at": ch.get("created_at"),
                "updated_at": ch.get("updated_at"),
                "member_count": ch.get("member_count", 0),
                "unread_count": unread,
                "last_message": last_message,
                "job_name": ch.get("job_name"),
                "job_number": ch.get("job_number"),
            })

        unread_mentions = await self.mention_repo.count_unread(user_id)

        return {
            "channels": channel_list,
            "total_unread": total_unread,
            "unread_mentions": unread_mentions,
        }

    async def get_channel_detail(
        self,
        channel_id: int,
        user_id: int,
        *,
        before_id: int | None = None,
        limit: int = 50,
    ) -> dict:
        """Get channel info + paginated messages + members + pinned.

        Also marks the channel as read up to the latest message.
        """
        # Verify membership
        if not await self.member_repo.is_member(channel_id, user_id):
            raise PermissionError("Not a member of this channel")

        # Fetch data in parallel-friendly order
        channel = dict(await self.channel_repo.get_by_id(channel_id))
        messages = await self.message_repo.get_messages(
            channel_id, before_id=before_id, limit=limit + 1
        )

        has_more = len(messages) > limit
        if has_more:
            messages = messages[1:]  # Remove oldest (we fetched limit+1 DESC)

        members = await self.member_repo.get_channel_members(channel_id)
        pinned = await self.message_repo.get_pinned(channel_id)

        # Auto-mark as read (latest message in this batch)
        if messages:
            latest_id = messages[-1]["id"]
            await self.read_repo.mark_read(channel_id, user_id, latest_id)

        return {
            "channel": channel,
            "messages": messages,
            "members": members,
            "pinned_messages": pinned,
            "has_more": has_more,
        }

    async def get_channel_members(self, channel_id: int) -> list[dict]:
        """Get all members of a channel."""
        return await self.member_repo.get_channel_members(channel_id)

    async def add_member(
        self, channel_id: int, user_id: int, role: str = "member"
    ) -> int:
        """Add a member to a channel."""
        return await self.member_repo.add_member(channel_id, user_id, role)

    async def remove_member(self, channel_id: int, user_id: int) -> bool:
        """Remove a member from a channel."""
        return await self.member_repo.remove_member(channel_id, user_id)

    # ── Messages ───────────────────────────────────────────────────

    async def send_message(
        self,
        channel_id: int,
        sender_id: int,
        content: str | None,
        *,
        message_type: str = "text",
        media_path: str | None = None,
        media_mime_type: str | None = None,
        media_size_bytes: int | None = None,
        reply_to_id: int | None = None,
        mention_ids: list[int] | None = None,
        qa_thread_id: int | None = None,
        qa_level: str | None = None,
    ) -> dict:
        """Send a message with membership validation and @mention processing.

        Flow:
        1. Validate sender is channel member
        2. Create message record
        3. Create mention records for each mentioned user
        4. Fire notifications for channel members + mentioned users
        5. Return message with sender info
        """
        # 1. Validate membership
        if not await self.member_repo.is_member(channel_id, sender_id):
            raise PermissionError("Not a member of this channel")

        # 2. Create message
        msg = await self.message_repo.create_message(
            channel_id=channel_id,
            sender_id=sender_id,
            content=content,
            message_type=message_type,
            media_path=media_path,
            media_mime_type=media_mime_type,
            media_size_bytes=media_size_bytes,
            reply_to_id=reply_to_id,
            qa_thread_id=qa_thread_id,
            qa_level=qa_level,
        )

        # 3. Process @mentions
        if mention_ids:
            # Filter to only channel members
            valid_mentions = []
            for mid in mention_ids:
                if mid != sender_id and await self.member_repo.is_member(
                    channel_id, mid
                ):
                    valid_mentions.append(mid)

            if valid_mentions:
                await self.mention_repo.create_mentions(
                    msg["id"], valid_mentions
                )

                # Fire mention notifications
                await self.notif_service.notify(
                    "chat_mention",
                    f"@mentioned you in chat",
                    message=(content or "")[:100],
                    link=f"/chat/inbox?channel={channel_id}",
                    entity_type="chat_message",
                    entity_id=msg["id"],
                    target_user_ids=valid_mentions,
                )

        # 4. Fire message notification to other members (not sender, not mentioned)
        members = await self.member_repo.get_channel_members(channel_id)
        other_ids = [
            m["user_id"]
            for m in members
            if m["user_id"] != sender_id
            and m["user_id"] not in (mention_ids or [])
        ]
        if other_ids:
            sender_name = msg.get("sender_name", "Someone")
            preview = (content or "[media]")[:60]
            await self.notif_service.notify(
                "chat_message",
                f"{sender_name}: {preview}",
                link=f"/chat/inbox?channel={channel_id}",
                entity_type="chat_message",
                entity_id=msg["id"],
                target_user_ids=other_ids,
            )

        return msg

    async def edit_message(
        self, message_id: int, content: str, editor_id: int
    ) -> bool:
        """Edit a message. Only the sender can edit."""
        row = await self.message_repo.get_by_id(message_id)
        if not row:
            raise ValueError("Message not found")
        if row["sender_id"] != editor_id:
            raise PermissionError("Can only edit your own messages")
        return await self.message_repo.edit_content(message_id, content)

    async def delete_message(self, message_id: int, deleter_id: int) -> bool:
        """Soft-delete a message. Sender or channel admin can delete."""
        row = await self.message_repo.get_by_id(message_id)
        if not row:
            raise ValueError("Message not found")
        if row["sender_id"] != deleter_id:
            raise PermissionError("Can only delete your own messages")
        return await self.message_repo.soft_delete(message_id)

    async def pin_message(self, message_id: int, pinned_by: int) -> bool:
        """Pin a message in its channel."""
        return await self.message_repo.pin(message_id, pinned_by)

    async def unpin_message(self, message_id: int) -> bool:
        """Unpin a message."""
        return await self.message_repo.unpin(message_id)

    # ── Read Receipts ──────────────────────────────────────────────

    async def mark_read(
        self, channel_id: int, user_id: int, message_id: int
    ) -> None:
        """Mark a channel as read up to a specific message."""
        await self.read_repo.mark_read(channel_id, user_id, message_id)

    # ── Mentions ───────────────────────────────────────────────────

    async def get_unread_mentions(self, user_id: int) -> list[dict]:
        """Get all unacknowledged @mentions for a user."""
        return await self.mention_repo.get_unread_mentions(user_id)

    async def acknowledge_mention(self, mention_id: int) -> bool:
        """Mark a mention as acknowledged."""
        return await self.mention_repo.acknowledge(mention_id)

    # ── Internal Helpers ───────────────────────────────────────────

    async def _get_job_crew(self, job_id: int) -> list[int]:
        """Get all user IDs associated with a job.

        Combines:
        - job_team_members (permanent crew assignments)
        - job_dispatch (daily dispatched workers)
        - jobs.lead_user_id (job lead)
        """
        user_ids: set[int] = set()

        # Job lead
        cursor = await self.db.execute(
            "SELECT lead_user_id FROM jobs WHERE id = ?", (job_id,)
        )
        job = await cursor.fetchone()
        if job and job["lead_user_id"]:
            user_ids.add(job["lead_user_id"])

        # Team members (if table exists — added in migration 037)
        try:
            cursor = await self.db.execute(
                "SELECT user_id FROM job_team_members WHERE job_id = ?",
                (job_id,),
            )
            for row in await cursor.fetchall():
                user_ids.add(row["user_id"])
        except Exception:
            pass  # Table may not exist yet

        # Dispatched workers (last 30 days of dispatches)
        try:
            cursor = await self.db.execute(
                """SELECT DISTINCT user_id FROM job_dispatch
                   WHERE job_id = ? AND dispatch_date >= date('now', '-30 days')""",
                (job_id,),
            )
            for row in await cursor.fetchall():
                user_ids.add(row["user_id"])
        except Exception:
            pass

        return list(user_ids)

    async def get_badge_count(self, user_id: int) -> dict:
        """Get combined unread count for the chat badge in the nav."""
        channels = await self.channel_repo.get_user_channels(user_id)
        total_unread = sum(ch.get("unread_count", 0) for ch in channels)
        unread_mentions = await self.mention_repo.count_unread(user_id)
        return {
            "total_unread": total_unread,
            "unread_mentions": unread_mentions,
        }
