/**
 * Chat, Q&A, & RFI API functions — channels, messages, mentions,
 * Q&A escalation, and RFI management.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type {
  ApiResponse,
  ChatChannelResponse,
  ChatChannelDetailResponse,
  ChatInboxResponse,
  ChatMessageResponse,
  ChatMentionResponse,
  ChatBadgeResponse,
  SendMessageRequest,
  EditMessageRequest,
  MarkReadRequest,
  QAThreadResponse,
  QAThreadDetailResponse,
  AskQuestionRequest,
  EscalateRequest,
  AnswerRequest,
  RFIResponse,
  SendToGCRequest,
  UpdateRFIRequest,
  StatusMessage,
} from '../lib/types';


// =================================================================
// CHANNELS
// =================================================================

/** Get user's inbox — all channels with unread counts. */
export async function getInbox(): Promise<ChatInboxResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ChatInboxResponse>>(
        '/chat/channels',
      );
      return data.data!;
    },
    async () => {
      const { getInbox: local } = await import('../local/services/chat-service');
      const channels = await local(0); // userId from local auth
      return { channels } as unknown as ChatInboxResponse;
    },
  );
}

/** Get channel detail with paginated messages and member list. */
export async function getChannelDetail(
  channelId: number,
  beforeId?: number,
  limit = 50,
): Promise<ChatChannelDetailResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ChatChannelDetailResponse>>(
        `/chat/channels/${channelId}`,
        { params: { before_id: beforeId, limit } },
      );
      return data.data!;
    },
    async () => {
      const { getChannelMessages, getChannelMembers, getPinnedMessages } = await import('../local/services/chat-service');
      const [msgData, members, pinned] = await Promise.all([
        getChannelMessages(channelId, { before_id: beforeId, limit }),
        getChannelMembers(channelId),
        getPinnedMessages(channelId),
      ]);
      return {
        messages: msgData.messages,
        has_more: msgData.has_more,
        members,
        pinned_messages: pinned,
      } as unknown as ChatChannelDetailResponse;
    },
  );
}

/** Create or find a DM channel between users. */
export async function createDMChannel(
  userIds: number[],
): Promise<ChatChannelResponse> {
  const { data } = await apiClient.post<ApiResponse<ChatChannelResponse>>(
    '/chat/channels/dm',
    { channel_type: 'dm', user_ids: userIds },
  );
  return data.data!;
}

/** Get or create a job channel with auto-enrollment. */
export async function getOrCreateJobChannel(
  jobId: number,
): Promise<ChatChannelResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ChatChannelResponse>>(
        `/chat/channels/job/${jobId}`,
      );
      return data.data!;
    },
    async () => {
      const { getOrCreateJobChannel: local } = await import('../local/services/chat-service');
      const channelId = await local(jobId, 0); // createdBy from local auth
      return { id: channelId, channel_type: 'job', job_id: jobId } as unknown as ChatChannelResponse;
    },
  );
}


// =================================================================
// MESSAGES
// =================================================================

/** Send a message to a channel. */
export async function sendMessage(
  channelId: number,
  body: SendMessageRequest,
): Promise<ChatMessageResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ChatMessageResponse>>(
        `/chat/channels/${channelId}/messages`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { sendMessage: local } = await import('../local/services/chat-service');
      const id = await local(channelId, 0, {
        content: body.content ?? undefined,
        message_type: body.message_type ?? undefined,
        media_path: body.media_path ?? undefined,
        reply_to_id: body.reply_to_id ?? undefined,
        mention_ids: body.mention_ids,
      }); // senderId from local auth
      return { id, channel_id: channelId, ...body } as unknown as ChatMessageResponse;
    },
  );
}

/** Edit a message (only sender can edit). */
export async function editMessage(
  messageId: number,
  body: EditMessageRequest,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<StatusMessage>>(
        `/chat/messages/${messageId}`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { editMessage: local } = await import('../local/services/chat-service');
      await local(messageId, body.content);
      return { status: 'ok', message: 'Message updated' } as StatusMessage;
    },
  );
}

/** Soft-delete a message (only sender can delete). */
export async function deleteMessage(
  messageId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
        `/chat/messages/${messageId}`,
      );
      return data.data!;
    },
    async () => {
      const { deleteMessage: local } = await import('../local/services/chat-service');
      await local(messageId);
      return { status: 'ok', message: 'Message deleted' } as StatusMessage;
    },
  );
}

/** Pin a message. */
export async function pinMessage(
  messageId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
        `/chat/messages/${messageId}/pin`,
      );
      return data.data!;
    },
    async () => {
      const { pinMessage: local } = await import('../local/services/chat-service');
      await local(messageId, 0); // userId from local auth
      return { status: 'ok', message: 'Message pinned' } as StatusMessage;
    },
  );
}

/** Unpin a message. */
export async function unpinMessage(
  messageId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
        `/chat/messages/${messageId}/pin`,
      );
      return data.data!;
    },
    async () => {
      const { unpinMessage: local } = await import('../local/services/chat-service');
      await local(messageId);
      return { status: 'ok', message: 'Message unpinned' } as StatusMessage;
    },
  );
}


// =================================================================
// READ RECEIPTS
// =================================================================

/** Mark a channel as read up to a specific message. */
export async function markChannelRead(
  channelId: number,
  body: MarkReadRequest,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
        `/chat/channels/${channelId}/read`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { markChannelRead: local } = await import('../local/services/chat-service');
      await local(channelId, 0, body.last_read_message_id); // userId from local auth
      return { status: 'ok', message: 'Channel marked as read' } as StatusMessage;
    },
  );
}


// =================================================================
// MENTIONS
// =================================================================

/** Get all unread @mentions for the current user. */
export async function getMentions(): Promise<ChatMentionResponse[]> {
  const { data } = await apiClient.get<ApiResponse<ChatMentionResponse[]>>(
    '/chat/mentions',
  );
  return data.data!;
}

/** Acknowledge a mention. */
export async function ackMention(
  mentionId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    `/chat/mentions/${mentionId}/ack`,
  );
  return data.data!;
}


// =================================================================
// BADGE COUNT
// =================================================================

/** Get unread count for the chat nav badge. */
export async function getChatBadge(): Promise<ChatBadgeResponse> {
  const { data } = await apiClient.get<ApiResponse<ChatBadgeResponse>>(
    '/chat/badge',
  );
  return data.data!;
}


// =================================================================
// Q&A THREADS
// =================================================================

/** Ask a Q&A question on a job. */
export async function askQuestion(
  body: AskQuestionRequest,
): Promise<QAThreadResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<QAThreadResponse>>(
        '/chat/qa/ask',
        body,
      );
      return data.data!;
    },
    async () => {
      const { askQuestion: local } = await import('../local/services/chat-service');
      const id = await local(body.job_id, 0, body.subject, body.body ?? '', body.priority);
      return { id, ...body, status: 'open' } as unknown as QAThreadResponse;
    },
  );
}

/** List Q&A threads with optional filters. */
export async function getQAThreads(params: {
  job_id?: number;
  status?: string;
  assigned_to?: number;
  priority?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<QAThreadResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<QAThreadResponse[]>>(
        '/chat/qa/threads',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { listQAThreads } = await import('../local/services/chat-service');
      return await listQAThreads(params) as unknown as QAThreadResponse[];
    },
  );
}

/** Get thread detail with messages and escalation timeline. */
export async function getQAThreadDetail(
  threadId: number,
): Promise<QAThreadDetailResponse> {
  const { data } = await apiClient.get<ApiResponse<QAThreadDetailResponse>>(
    `/chat/qa/threads/${threadId}`,
  );
  return data.data!;
}

/** Escalate a Q&A thread to the next level. */
export async function escalateThread(
  threadId: number,
  body: EscalateRequest = {},
): Promise<QAThreadResponse> {
  const { data } = await apiClient.post<ApiResponse<QAThreadResponse>>(
    `/chat/qa/threads/${threadId}/escalate`,
    body,
  );
  return data.data!;
}

/** Answer a Q&A thread. */
export async function answerThread(
  threadId: number,
  body: AnswerRequest,
): Promise<QAThreadResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<QAThreadResponse>>(
        `/chat/qa/threads/${threadId}/answer`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { answerQuestion } = await import('../local/services/chat-service');
      await answerQuestion(threadId, 0, body.answer); // answeredBy from local auth
      return { id: threadId, status: 'answered' } as unknown as QAThreadResponse;
    },
  );
}

/** Close a Q&A thread. */
export async function closeThread(
  threadId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    `/chat/qa/threads/${threadId}/close`,
  );
  return data.data!;
}

/** Create RFI and prepare for GC communication. */
export async function sendToGC(
  threadId: number,
  body: SendToGCRequest,
): Promise<RFIResponse> {
  const { data } = await apiClient.post<ApiResponse<RFIResponse>>(
    `/chat/qa/threads/${threadId}/send-to-gc`,
    body,
  );
  return data.data!;
}


// =================================================================
// RFIS
// =================================================================

/** List RFIs with optional filters. */
export async function getRFIs(params: {
  job_id?: number;
  status?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<RFIResponse[]> {
  const { data } = await apiClient.get<ApiResponse<RFIResponse[]>>(
    '/chat/rfis',
    { params },
  );
  return data.data!;
}

/** Update RFI status (e.g., mark as responded). */
export async function updateRFI(
  rfiId: number,
  body: UpdateRFIRequest,
): Promise<StatusMessage> {
  const { data } = await apiClient.patch<ApiResponse<StatusMessage>>(
    `/chat/rfis/${rfiId}`,
    body,
  );
  return data.data!;
}
