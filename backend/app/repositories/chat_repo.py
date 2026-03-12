"""
Chat repository — channels, messages, read receipts, mentions.

Handles all chat-related database operations. Q&A and RFI operations
are in qa_repo.py.
"""

from __future__ import annotations

from app.repositories.base import BaseRepo


class ChatChannelRepo(BaseRepo):
    """Repository for the `chat_channels` table."""
    TABLE = "chat_channels"
    HAS_UPDATED_AT = True

    async def get_or_create_job_channel(self, job_id: int, created_by: int) -> dict:
        """Get existing job channel or create one. Returns channel dict."""
        cursor = await self.db.execute(
            "SELECT * FROM chat_channels WHERE channel_type = 'job' AND job_id = ?",
            (job_id,),
        )
        row = await cursor.fetchone()
        if row:
            return dict(row)

        # Create channel named after the job
        cursor = await self.db.execute(
            """SELECT job_number, job_name FROM jobs WHERE id = ?""",
            (job_id,),
        )
        job = await cursor.fetchone()
        name = f"{job['job_number']} – {job['job_name']}" if job else f"Job #{job_id}"

        new_id = await self.insert({
            "channel_type": "job",
            "job_id": job_id,
            "name": name,
            "created_by": created_by,
        })
        return dict(await self.get_by_id(new_id))

    async def find_dm_channel(self, user_ids: list[int]) -> dict | None:
        """Find existing DM channel between exactly these users."""
        if len(user_ids) != 2:
            return None

        cursor = await self.db.execute(
            """
            SELECT cc.* FROM chat_channels cc
            WHERE cc.channel_type = 'dm'
              AND (SELECT COUNT(*) FROM chat_channel_members m
                   WHERE m.channel_id = cc.id) = 2
              AND EXISTS (SELECT 1 FROM chat_channel_members m
                          WHERE m.channel_id = cc.id AND m.user_id = ?)
              AND EXISTS (SELECT 1 FROM chat_channel_members m
                          WHERE m.channel_id = cc.id AND m.user_id = ?)
            LIMIT 1
            """,
            (user_ids[0], user_ids[1]),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def create_dm_channel(self, user_ids: list[int], created_by: int) -> dict:
        """Create a DM channel and add members. Deduplicates 2-person DMs."""
        existing = await self.find_dm_channel(user_ids)
        if existing:
            return existing

        new_id = await self.insert({
            "channel_type": "dm",
            "name": None,
            "created_by": created_by,
        })

        member_repo = ChatMemberRepo(self.db)
        for uid in user_ids:
            await member_repo.insert({
                "channel_id": new_id,
                "user_id": uid,
                "role": "member",
            })

        return dict(await self.get_by_id(new_id))

    async def get_user_channels(self, user_id: int) -> list[dict]:
        """Get all channels for a user with unread counts and last message preview."""
        cursor = await self.db.execute(
            """
            SELECT cc.*,
                   j.job_name, j.job_number,
                   (SELECT COUNT(*) FROM chat_channel_members m
                    WHERE m.channel_id = cc.id) AS member_count,
                   -- Unread count
                   (SELECT COUNT(*) FROM chat_messages cm
                    WHERE cm.channel_id = cc.id
                      AND cm.deleted_at IS NULL
                      AND cm.id > COALESCE(
                          (SELECT last_read_message_id FROM chat_read_receipts
                           WHERE channel_id = cc.id AND user_id = ?), 0)
                      AND cm.sender_id != ?) AS unread_count,
                   -- Last message preview
                   lm.id AS last_msg_id,
                   lm.content AS last_msg_content,
                   lm.message_type AS last_msg_type,
                   lm.created_at AS last_msg_at,
                   lu.display_name AS last_msg_sender
            FROM chat_channels cc
            INNER JOIN chat_channel_members ccm ON ccm.channel_id = cc.id
            LEFT JOIN jobs j ON j.id = cc.job_id
            LEFT JOIN (
                SELECT channel_id, MAX(id) AS max_id
                FROM chat_messages WHERE deleted_at IS NULL
                GROUP BY channel_id
            ) lmx ON lmx.channel_id = cc.id
            LEFT JOIN chat_messages lm ON lm.id = lmx.max_id
            LEFT JOIN users lu ON lu.id = lm.sender_id
            WHERE ccm.user_id = ?
            ORDER BY COALESCE(lm.created_at, cc.created_at) DESC
            """,
            (user_id, user_id, user_id),
        )
        return [dict(r) for r in await cursor.fetchall()]


class ChatMemberRepo(BaseRepo):
    """Repository for the `chat_channel_members` table."""
    TABLE = "chat_channel_members"
    HAS_UPDATED_AT = False

    async def get_channel_members(self, channel_id: int) -> list[dict]:
        """Get all members of a channel with user info."""
        cursor = await self.db.execute(
            """
            SELECT ccm.*, u.display_name, u.username
            FROM chat_channel_members ccm
            JOIN users u ON u.id = ccm.user_id
            WHERE ccm.channel_id = ?
            ORDER BY u.display_name
            """,
            (channel_id,),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def is_member(self, channel_id: int, user_id: int) -> bool:
        """Check if a user is a member of a channel."""
        cursor = await self.db.execute(
            "SELECT 1 FROM chat_channel_members WHERE channel_id = ? AND user_id = ? LIMIT 1",
            (channel_id, user_id),
        )
        return await cursor.fetchone() is not None

    async def add_member(self, channel_id: int, user_id: int, role: str = "member") -> int:
        """Add a member to a channel. Returns member record id."""
        return await self.insert({
            "channel_id": channel_id,
            "user_id": user_id,
            "role": role,
        })

    async def remove_member(self, channel_id: int, user_id: int) -> bool:
        """Remove a member from a channel."""
        cursor = await self.db.execute(
            "DELETE FROM chat_channel_members WHERE channel_id = ? AND user_id = ?",
            (channel_id, user_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0


class ChatMessageRepo(BaseRepo):
    """Repository for the `chat_messages` table."""
    TABLE = "chat_messages"
    HAS_UPDATED_AT = False

    async def get_messages(
        self,
        channel_id: int,
        *,
        before_id: int | None = None,
        limit: int = 50,
    ) -> list[dict]:
        """Get messages for a channel with cursor-based pagination.

        Returns messages in ascending order (oldest first within page).
        `before_id` is the cursor — fetch messages older than this ID.
        """
        conditions = ["cm.channel_id = ?", "cm.deleted_at IS NULL"]
        params: list = [channel_id]

        if before_id:
            conditions.append("cm.id < ?")
            params.append(before_id)

        where = " AND ".join(conditions)
        params.append(limit)

        cursor = await self.db.execute(
            f"""
            SELECT cm.*,
                   u.display_name AS sender_name,
                   u.username AS sender_username,
                   rp.content AS reply_preview,
                   ru.display_name AS reply_sender_name
            FROM chat_messages cm
            JOIN users u ON u.id = cm.sender_id
            LEFT JOIN chat_messages rp ON rp.id = cm.reply_to_id
            LEFT JOIN users ru ON ru.id = rp.sender_id
            WHERE {where}
            ORDER BY cm.id DESC
            LIMIT ?
            """,
            tuple(params),
        )
        rows = [dict(r) for r in await cursor.fetchall()]
        rows.reverse()  # Return in chronological order
        return rows

    async def create_message(
        self,
        channel_id: int,
        sender_id: int,
        content: str | None,
        message_type: str = "text",
        media_path: str | None = None,
        media_mime_type: str | None = None,
        media_size_bytes: int | None = None,
        reply_to_id: int | None = None,
        qa_thread_id: int | None = None,
        qa_level: str | None = None,
    ) -> dict:
        """Create a message and return it with sender info."""
        data = {
            "channel_id": channel_id,
            "sender_id": sender_id,
            "content": content,
            "message_type": message_type,
        }
        if media_path:
            data["media_path"] = media_path
        if media_mime_type:
            data["media_mime_type"] = media_mime_type
        if media_size_bytes:
            data["media_size_bytes"] = media_size_bytes
        if reply_to_id:
            data["reply_to_id"] = reply_to_id
        if qa_thread_id:
            data["qa_thread_id"] = qa_thread_id
        if qa_level:
            data["qa_level"] = qa_level

        new_id = await self.insert(data)

        # Update channel's updated_at
        await self.db.execute(
            "UPDATE chat_channels SET updated_at = datetime('now') WHERE id = ?",
            (channel_id,),
        )
        await self.db.commit()

        # Return with sender info
        cursor = await self.db.execute(
            """
            SELECT cm.*, u.display_name AS sender_name, u.username AS sender_username
            FROM chat_messages cm
            JOIN users u ON u.id = cm.sender_id
            WHERE cm.id = ?
            """,
            (new_id,),
        )
        return dict(await cursor.fetchone())

    async def soft_delete(self, message_id: int) -> bool:
        """Soft-delete a message."""
        cursor = await self.db.execute(
            "UPDATE chat_messages SET deleted_at = datetime('now') WHERE id = ?",
            (message_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def edit_content(self, message_id: int, content: str) -> bool:
        """Edit message content."""
        cursor = await self.db.execute(
            """UPDATE chat_messages
               SET content = ?, edited_at = datetime('now')
               WHERE id = ? AND deleted_at IS NULL""",
            (content, message_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def pin(self, message_id: int, pinned_by: int) -> bool:
        """Pin a message."""
        cursor = await self.db.execute(
            "UPDATE chat_messages SET pinned_at = datetime('now'), pinned_by = ? WHERE id = ?",
            (pinned_by, message_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def unpin(self, message_id: int) -> bool:
        """Unpin a message."""
        cursor = await self.db.execute(
            "UPDATE chat_messages SET pinned_at = NULL, pinned_by = NULL WHERE id = ?",
            (message_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def get_pinned(self, channel_id: int) -> list[dict]:
        """Get all pinned messages for a channel."""
        cursor = await self.db.execute(
            """
            SELECT cm.*, u.display_name AS sender_name, u.username AS sender_username
            FROM chat_messages cm
            JOIN users u ON u.id = cm.sender_id
            WHERE cm.channel_id = ? AND cm.pinned_at IS NOT NULL AND cm.deleted_at IS NULL
            ORDER BY cm.pinned_at DESC
            """,
            (channel_id,),
        )
        return [dict(r) for r in await cursor.fetchall()]


class ChatReadReceiptRepo(BaseRepo):
    """Repository for the `chat_read_receipts` table."""
    TABLE = "chat_read_receipts"
    HAS_UPDATED_AT = False

    async def mark_read(self, channel_id: int, user_id: int, message_id: int) -> None:
        """Mark a channel as read up to the given message."""
        await self.db.execute(
            """INSERT INTO chat_read_receipts (channel_id, user_id, last_read_message_id, read_at)
               VALUES (?, ?, ?, datetime('now'))
               ON CONFLICT(channel_id, user_id)
               DO UPDATE SET last_read_message_id = MAX(last_read_message_id, excluded.last_read_message_id),
                             read_at = datetime('now')""",
            (channel_id, user_id, message_id),
        )
        await self.db.commit()

    async def get_unread_count(self, channel_id: int, user_id: int) -> int:
        """Get unread message count for a user in a channel."""
        cursor = await self.db.execute(
            """
            SELECT COUNT(*) AS cnt FROM chat_messages cm
            WHERE cm.channel_id = ?
              AND cm.deleted_at IS NULL
              AND cm.id > COALESCE(
                  (SELECT last_read_message_id FROM chat_read_receipts
                   WHERE channel_id = ? AND user_id = ?), 0)
              AND cm.sender_id != ?
            """,
            (channel_id, channel_id, user_id, user_id),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0


class ChatMentionRepo(BaseRepo):
    """Repository for the `chat_mentions` table."""
    TABLE = "chat_mentions"
    HAS_UPDATED_AT = False

    async def create_mentions(self, message_id: int, user_ids: list[int]) -> None:
        """Batch-insert mention records for a message."""
        for uid in user_ids:
            await self.db.execute(
                "INSERT INTO chat_mentions (message_id, mentioned_user_id) VALUES (?, ?)",
                (message_id, uid),
            )
        await self.db.commit()

    async def get_unread_mentions(self, user_id: int) -> list[dict]:
        """Get all unacknowledged mentions for a user."""
        cursor = await self.db.execute(
            """
            SELECT cm_ment.*, msg.content, msg.channel_id, msg.created_at,
                   u.display_name AS sender_name,
                   cc.name AS channel_name, cc.job_id
            FROM chat_mentions cm_ment
            JOIN chat_messages msg ON msg.id = cm_ment.message_id
            JOIN users u ON u.id = msg.sender_id
            JOIN chat_channels cc ON cc.id = msg.channel_id
            WHERE cm_ment.mentioned_user_id = ?
              AND cm_ment.acknowledged_at IS NULL
              AND msg.deleted_at IS NULL
            ORDER BY msg.created_at DESC
            """,
            (user_id,),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def acknowledge(self, mention_id: int) -> bool:
        """Mark a mention as acknowledged."""
        cursor = await self.db.execute(
            "UPDATE chat_mentions SET acknowledged_at = datetime('now') WHERE id = ?",
            (mention_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def count_unread(self, user_id: int) -> int:
        """Count unacknowledged mentions for a user."""
        cursor = await self.db.execute(
            """SELECT COUNT(*) AS cnt FROM chat_mentions cm_ment
               JOIN chat_messages msg ON msg.id = cm_ment.message_id
               WHERE cm_ment.mentioned_user_id = ?
                 AND cm_ment.acknowledged_at IS NULL
                 AND msg.deleted_at IS NULL""",
            (user_id,),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0
