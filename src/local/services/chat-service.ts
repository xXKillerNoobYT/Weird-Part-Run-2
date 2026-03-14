/**
 * Local Chat Service — offline read/write for messages, channels, and Q&A.
 *
 * Mirrors backend/app/services/chat_service.py + qa_service.py
 * for field workers. Supports: channel list/detail, message CRUD,
 * read receipts, Q&A threads, and offline message queuing.
 *
 * RFI management is shop-only — synced down for visibility only.
 */

import { getDb } from '../db';
import { trackChange } from '../change-tracker';
import { BaseRepo } from '../repos/base-repo';

// ── Repos ──────────────────────────────────────────────────────────

const channelRepo = new BaseRepo('chat_channels');
const memberRepo = new BaseRepo('chat_channel_members');
const messageRepo = new BaseRepo('chat_messages');
const mentionRepo = new BaseRepo('chat_mentions');
const qaRepo = new BaseRepo('qa_threads');

// ── Types ──────────────────────────────────────────────────────────

export interface LocalChannel {
  id: number;
  channel_type: string;
  job_id: number | null;
  name: string | null;
  created_by: number;
  is_active: number;
  created_at: string;
  updated_at: string;
  // Joined
  job_name?: string;
  job_number?: string;
  display_name?: string;
  unread_count?: number;
  last_message_preview?: string;
  last_message_at?: string;
  member_count?: number;
}

export interface LocalMessage {
  id: number;
  channel_id: number;
  sender_id: number;
  message_type: string;
  content: string | null;
  media_path: string | null;
  reply_to_id: number | null;
  pinned_at: string | null;
  qa_thread_id: number | null;
  qa_level: string | null;
  edited_at: string | null;
  deleted_at: string | null;
  created_at: string;
  // Joined
  sender_name?: string;
  reply_preview?: string;
  reply_sender_name?: string;
}

export interface LocalQAThread {
  id: number;
  channel_id: number | null;
  job_id: number;
  asked_by: number;
  subject: string;
  current_level: string;
  assigned_to: number | null;
  status: string;
  priority: string;
  answer_text: string | null;
  answered_by: number | null;
  answered_at: string | null;
  closed_at: string | null;
  created_at: string;
  updated_at: string;
  // Joined
  asker_name?: string;
  assigned_name?: string;
  job_number?: string;
}

// ── Inbox ──────────────────────────────────────────────────────────

/** Get channels the user belongs to, with unread counts and last message preview */
export async function getInbox(userId: number): Promise<LocalChannel[]> {
  const db = await getDb();

  const result = await db.query(
    `SELECT cc.*,
       j.job_name, j.job_number,
       (SELECT COUNT(*) FROM chat_channel_members WHERE channel_id = cc.id) as member_count,
       (SELECT cm.content FROM chat_messages cm
        WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
        ORDER BY cm.created_at DESC LIMIT 1) as last_message_preview,
       (SELECT cm.created_at FROM chat_messages cm
        WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
        ORDER BY cm.created_at DESC LIMIT 1) as last_message_at,
       (SELECT COUNT(*) FROM chat_messages cm
        WHERE cm.channel_id = cc.id
          AND cm.deleted_at IS NULL
          AND cm.sender_id != ?
          AND cm.id > COALESCE(
            (SELECT last_read_message_id FROM chat_read_receipts
             WHERE channel_id = cc.id AND user_id = ?), 0)
       ) as unread_count
     FROM chat_channels cc
     JOIN chat_channel_members ccm ON ccm.channel_id = cc.id
     LEFT JOIN jobs j ON j.id = cc.job_id
     WHERE ccm.user_id = ? AND ccm.left_at IS NULL AND cc.is_active = 1
     ORDER BY last_message_at DESC NULLS LAST`,
    [userId, userId, userId],
  );
  return result.values as LocalChannel[];
}

// ── Channel Detail ────────────────────────────────────────────────

/** Get messages for a channel (cursor-based, newest first) */
export async function getChannelMessages(
  channelId: number,
  opts?: { before_id?: number; limit?: number },
): Promise<{ messages: LocalMessage[]; has_more: boolean }> {
  const db = await getDb();
  const limit = opts?.limit ?? 50;

  const conditions = ['cm.channel_id = ?', 'cm.deleted_at IS NULL'];
  const params: any[] = [channelId];

  if (opts?.before_id) {
    conditions.push('cm.id < ?');
    params.push(opts.before_id);
  }

  const where = conditions.join(' AND ');
  params.push(limit + 1); // +1 for has_more

  const result = await db.query(
    `SELECT cm.*,
       u.display_name as sender_name,
       reply.content as reply_preview,
       ru.display_name as reply_sender_name
     FROM chat_messages cm
     JOIN users u ON u.id = cm.sender_id
     LEFT JOIN chat_messages reply ON reply.id = cm.reply_to_id
     LEFT JOIN users ru ON ru.id = reply.sender_id
     WHERE ${where}
     ORDER BY cm.created_at DESC
     LIMIT ?`,
    params,
  );

  const rows = result.values as LocalMessage[];
  const has_more = rows.length > limit;
  if (has_more) rows.pop();

  // Return in chronological order (oldest first)
  return { messages: rows.reverse(), has_more };
}

/** Get channel members */
export async function getChannelMembers(channelId: number) {
  const db = await getDb();
  const result = await db.query(
    `SELECT ccm.*, u.display_name, u.username
     FROM chat_channel_members ccm
     JOIN users u ON u.id = ccm.user_id
     WHERE ccm.channel_id = ? AND ccm.left_at IS NULL`,
    [channelId],
  );
  return result.values;
}

/** Get pinned messages for a channel */
export async function getPinnedMessages(channelId: number): Promise<LocalMessage[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT cm.*, u.display_name as sender_name
     FROM chat_messages cm
     JOIN users u ON u.id = cm.sender_id
     WHERE cm.channel_id = ? AND cm.pinned_at IS NOT NULL AND cm.deleted_at IS NULL
     ORDER BY cm.pinned_at DESC`,
    [channelId],
  );
  return result.values as LocalMessage[];
}

// ── Message CRUD ──────────────────────────────────────────────────

/** Send a message (queued for sync) */
export async function sendMessage(
  channelId: number,
  senderId: number,
  opts: {
    content?: string;
    message_type?: string;
    media_path?: string;
    reply_to_id?: number;
    mention_ids?: number[];
  },
): Promise<number> {
  const id = await messageRepo.insert({
    channel_id: channelId,
    sender_id: senderId,
    message_type: opts.message_type ?? 'text',
    content: opts.content ?? null,
    media_path: opts.media_path ?? null,
    reply_to_id: opts.reply_to_id ?? null,
  });

  await trackChange('chat_messages', id, 'INSERT');

  // Create mention records
  if (opts.mention_ids?.length) {
    for (const mentionedUserId of opts.mention_ids) {
      const mId = await mentionRepo.insert({
        message_id: id,
        mentioned_user_id: mentionedUserId,
      });
      await trackChange('chat_mentions', mId, 'INSERT');
    }
  }

  // Update channel's updated_at
  await channelRepo.update(channelId, { updated_at: new Date().toISOString() });
  await trackChange('chat_channels', channelId, 'UPDATE');

  return id;
}

/** Edit a message */
export async function editMessage(messageId: number, content: string): Promise<void> {
  await messageRepo.update(messageId, {
    content,
    edited_at: new Date().toISOString(),
  });
  await trackChange('chat_messages', messageId, 'UPDATE');
}

/** Soft-delete a message */
export async function deleteMessage(messageId: number): Promise<void> {
  await messageRepo.update(messageId, {
    deleted_at: new Date().toISOString(),
  });
  await trackChange('chat_messages', messageId, 'UPDATE');
}

/** Pin/unpin a message */
export async function pinMessage(messageId: number, userId: number): Promise<void> {
  await messageRepo.update(messageId, {
    pinned_at: new Date().toISOString(),
    pinned_by: userId,
  });
  await trackChange('chat_messages', messageId, 'UPDATE');
}

export async function unpinMessage(messageId: number): Promise<void> {
  await messageRepo.update(messageId, {
    pinned_at: null,
    pinned_by: null,
  });
  await trackChange('chat_messages', messageId, 'UPDATE');
}

// ── Read Receipts ─────────────────────────────────────────────────

/** Mark channel as read up to a message ID (UPSERT) */
export async function markChannelRead(
  channelId: number,
  userId: number,
  lastReadMessageId: number,
): Promise<void> {
  const db = await getDb();
  await db.run(
    `INSERT INTO chat_read_receipts (channel_id, user_id, last_read_message_id, read_at)
     VALUES (?, ?, ?, datetime('now'))
     ON CONFLICT(channel_id, user_id)
     DO UPDATE SET last_read_message_id = MAX(last_read_message_id, excluded.last_read_message_id),
                   read_at = datetime('now')`,
    [channelId, userId, lastReadMessageId],
  );
}

// ── Q&A Threads ───────────────────────────────────────────────────

/** List Q&A threads with optional filters */
export async function listQAThreads(opts?: {
  job_id?: number;
  status?: string;
  assigned_to?: number;
  limit?: number;
}): Promise<LocalQAThread[]> {
  const db = await getDb();
  const conditions: string[] = [];
  const params: any[] = [];

  if (opts?.job_id) {
    conditions.push('qt.job_id = ?');
    params.push(opts.job_id);
  }
  if (opts?.status) {
    conditions.push('qt.status = ?');
    params.push(opts.status);
  }
  if (opts?.assigned_to) {
    conditions.push('qt.assigned_to = ?');
    params.push(opts.assigned_to);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  params.push(opts?.limit ?? 100);

  const result = await db.query(
    `SELECT qt.*,
       ua.display_name as asker_name,
       uas.display_name as assigned_name,
       j.job_number
     FROM qa_threads qt
     JOIN users ua ON ua.id = qt.asked_by
     LEFT JOIN users uas ON uas.id = qt.assigned_to
     JOIN jobs j ON j.id = qt.job_id
     ${where}
     ORDER BY qt.updated_at DESC
     LIMIT ?`,
    params,
  );
  return result.values as LocalQAThread[];
}

/** Ask a new question — creates a Q&A thread + system message */
export async function askQuestion(
  jobId: number,
  askedBy: number,
  subject: string,
  _body: string,
  priority: string = 'normal',
): Promise<number> {
  const id = await qaRepo.insert({
    job_id: jobId,
    asked_by: askedBy,
    subject,
    status: 'open',
    priority,
    current_level: 'worker',
  });
  await trackChange('qa_threads', id, 'INSERT');
  return id;
}

/** Answer a Q&A thread */
export async function answerQuestion(
  threadId: number,
  answeredBy: number,
  answerText: string,
): Promise<void> {
  await qaRepo.update(threadId, {
    status: 'answered',
    answer_text: answerText,
    answered_by: answeredBy,
    answered_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  });
  await trackChange('qa_threads', threadId, 'UPDATE');
}

/** Get Q&A thread detail with messages and escalation timeline */
export async function getQAThreadDetail(threadId: number): Promise<{
  thread: LocalQAThread;
  messages: LocalMessage[];
  timeline: any[];
  rfi: any | null;
}> {
  const db = await getDb();

  // Thread
  const threadResult = await db.query(
    `SELECT qt.*,
       ua.display_name as asker_name,
       uas.display_name as assigned_name,
       j.job_number
     FROM qa_threads qt
     JOIN users ua ON ua.id = qt.asked_by
     LEFT JOIN users uas ON uas.id = qt.assigned_to
     JOIN jobs j ON j.id = qt.job_id
     WHERE qt.id = ?`,
    [threadId],
  );
  const thread = threadResult.values[0] as LocalQAThread;

  // Messages linked to this thread
  const msgResult = await db.query(
    `SELECT cm.*, u.display_name as sender_name
     FROM chat_messages cm
     JOIN users u ON u.id = cm.sender_id
     WHERE cm.qa_thread_id = ? AND cm.deleted_at IS NULL
     ORDER BY cm.created_at ASC`,
    [threadId],
  );
  const messages = msgResult.values as LocalMessage[];

  // Build timeline from messages
  const timeline: any[] = [];
  for (const msg of messages) {
    if (['qa_question', 'qa_escalation', 'qa_answer', 'system'].includes(msg.message_type)) {
      timeline.push({
        level: msg.qa_level ?? thread.current_level,
        action: msg.message_type === 'qa_question' ? 'asked'
          : msg.message_type === 'qa_escalation' ? 'escalated'
          : msg.message_type === 'qa_answer' ? 'answered'
          : msg.content?.includes('closed') ? 'closed' : 'comment',
        user_name: msg.sender_name,
        comment: msg.content,
        timestamp: msg.created_at,
      });
    }
  }

  // RFI linked to this thread (if any)
  const rfiResult = await db.query(
    `SELECT * FROM rfi_objects WHERE qa_thread_id = ? LIMIT 1`,
    [threadId],
  );
  const rfi = rfiResult.values.length > 0 ? rfiResult.values[0] : null;

  return { thread, messages, timeline, rfi };
}

/** Escalate a Q&A thread to the next level */
const ESCALATION_CHAIN = ['worker', 'lead', 'foreman', 'supervisor', 'office'];

export async function escalateThread(
  threadId: number,
  escalatedBy: number,
  comment?: string,
): Promise<void> {
  const db = await getDb();
  const threadResult = await db.query('SELECT * FROM qa_threads WHERE id = ?', [threadId]);
  const thread = threadResult.values[0] as any;
  if (!thread) return;

  const currentIdx = ESCALATION_CHAIN.indexOf(thread.current_level);
  const nextLevel = currentIdx < ESCALATION_CHAIN.length - 1
    ? ESCALATION_CHAIN[currentIdx + 1]
    : thread.current_level;

  await qaRepo.update(threadId, {
    current_level: nextLevel,
    status: 'escalated',
    updated_at: new Date().toISOString(),
  });
  await trackChange('qa_threads', threadId, 'UPDATE');

  // Create escalation system message
  const userName = await db.query('SELECT display_name FROM users WHERE id = ?', [escalatedBy]);
  const name = (userName.values[0] as any)?.display_name ?? 'Unknown';
  const msgContent = comment
    ? `Escalated to ${nextLevel} by ${name}: ${comment}`
    : `Escalated to ${nextLevel} by ${name}`;

  const msgId = await messageRepo.insert({
    channel_id: thread.channel_id,
    sender_id: escalatedBy,
    message_type: 'qa_escalation',
    content: msgContent,
    qa_thread_id: threadId,
    qa_level: nextLevel,
  });
  await trackChange('chat_messages', msgId, 'INSERT');
}

/** Close a Q&A thread */
export async function closeThread(threadId: number): Promise<void> {
  await qaRepo.update(threadId, {
    status: 'closed',
    closed_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  });
  await trackChange('qa_threads', threadId, 'UPDATE');
}

// ── RFI (read-only on devices — synced from shop) ───────────────

/** List RFIs from local DB (synced down from shop) */
export async function listRFIs(opts?: {
  job_id?: number;
  status?: string;
  limit?: number;
}): Promise<any[]> {
  const db = await getDb();
  const conditions: string[] = [];
  const params: any[] = [];

  if (opts?.job_id) {
    conditions.push('r.job_id = ?');
    params.push(opts.job_id);
  }
  if (opts?.status) {
    conditions.push('r.status = ?');
    params.push(opts.status);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  params.push(opts?.limit ?? 100);

  const result = await db.query(
    `SELECT r.*, j.job_number, j.job_name
     FROM rfi_objects r
     JOIN jobs j ON j.id = r.job_id
     ${where}
     ORDER BY r.created_at DESC
     LIMIT ?`,
    params,
  );
  return result.values;
}

// ── Channel Creation ──────────────────────────────────────────────

/** Find or create a DM channel between users */
export async function createDMChannel(
  currentUserId: number,
  userIds: number[],
): Promise<LocalChannel> {
  const db = await getDb();
  const allIds = Array.from(new Set([currentUserId, ...userIds])).sort((a, b) => a - b);

  // Check for existing DM channel with exactly these members
  if (allIds.length === 2) {
    const existing = await db.query(
      `SELECT c.* FROM chat_channels c
       WHERE c.channel_type = 'dm' AND c.is_active = 1
       AND (SELECT COUNT(*) FROM chat_channel_members m WHERE m.channel_id = c.id) = 2
       AND EXISTS (SELECT 1 FROM chat_channel_members m WHERE m.channel_id = c.id AND m.user_id = ?)
       AND EXISTS (SELECT 1 FROM chat_channel_members m WHERE m.channel_id = c.id AND m.user_id = ?)`,
      [allIds[0], allIds[1]],
    );
    if (existing.values.length > 0) {
      return existing.values[0] as LocalChannel;
    }
  }

  // Build a display name from member names
  const otherIds = allIds.filter(id => id !== currentUserId);
  const namesResult = await db.query(
    `SELECT display_name FROM users WHERE id IN (${otherIds.map(() => '?').join(',')})`,
    otherIds,
  );
  const channelName = (namesResult.values as any[]).map(r => r.display_name).join(', ') || 'Direct Message';

  // Create new DM channel
  const id = await channelRepo.insert({
    channel_type: 'dm',
    job_id: null,
    name: channelName,
    created_by: currentUserId,
    is_active: 1,
  });
  await trackChange('chat_channels', id, 'INSERT');

  // Add all members
  for (const uid of allIds) {
    const mId = await memberRepo.insert({
      channel_id: id,
      user_id: uid,
      role: uid === currentUserId ? 'admin' : 'member',
    });
    await trackChange('chat_channel_members', mId, 'INSERT');
  }

  const channel = await channelRepo.getById(id);
  return channel as LocalChannel;
}

/** Find or create a job channel */
export async function getOrCreateJobChannel(
  jobId: number,
  createdBy: number,
): Promise<number> {
  const db = await getDb();

  // Check for existing
  const existing = await db.query(
    `SELECT id FROM chat_channels WHERE channel_type = 'job' AND job_id = ? AND is_active = 1`,
    [jobId],
  );

  if (existing.values.length > 0) {
    return existing.values[0].id;
  }

  // Create new channel
  const id = await channelRepo.insert({
    channel_type: 'job',
    job_id: jobId,
    created_by: createdBy,
  });
  await trackChange('chat_channels', id, 'INSERT');

  // Add creator as first member
  const mId = await memberRepo.insert({
    channel_id: id,
    user_id: createdBy,
    role: 'admin',
  });
  await trackChange('chat_channel_members', mId, 'INSERT');

  return id;
}
