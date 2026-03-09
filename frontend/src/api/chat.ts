/**
 * Chat, Q&A, & RFI API functions — channels, messages, mentions,
 * Q&A escalation, and RFI management.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
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
  const { data } = await apiClient.get<ApiResponse<ChatInboxResponse>>(
    '/chat/channels',
  );
  return data.data!;
}

/** Get channel detail with paginated messages and member list. */
export async function getChannelDetail(
  channelId: number,
  beforeId?: number,
  limit = 50,
): Promise<ChatChannelDetailResponse> {
  const { data } = await apiClient.get<ApiResponse<ChatChannelDetailResponse>>(
    `/chat/channels/${channelId}`,
    { params: { before_id: beforeId, limit } },
  );
  return data.data!;
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
  const { data } = await apiClient.post<ApiResponse<ChatChannelResponse>>(
    `/chat/channels/job/${jobId}`,
  );
  return data.data!;
}


// =================================================================
// MESSAGES
// =================================================================

/** Send a message to a channel. */
export async function sendMessage(
  channelId: number,
  body: SendMessageRequest,
): Promise<ChatMessageResponse> {
  const { data } = await apiClient.post<ApiResponse<ChatMessageResponse>>(
    `/chat/channels/${channelId}/messages`,
    body,
  );
  return data.data!;
}

/** Edit a message (only sender can edit). */
export async function editMessage(
  messageId: number,
  body: EditMessageRequest,
): Promise<StatusMessage> {
  const { data } = await apiClient.patch<ApiResponse<StatusMessage>>(
    `/chat/messages/${messageId}`,
    body,
  );
  return data.data!;
}

/** Soft-delete a message (only sender can delete). */
export async function deleteMessage(
  messageId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/chat/messages/${messageId}`,
  );
  return data.data!;
}

/** Pin a message. */
export async function pinMessage(
  messageId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    `/chat/messages/${messageId}/pin`,
  );
  return data.data!;
}

/** Unpin a message. */
export async function unpinMessage(
  messageId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/chat/messages/${messageId}/pin`,
  );
  return data.data!;
}


// =================================================================
// READ RECEIPTS
// =================================================================

/** Mark a channel as read up to a specific message. */
export async function markChannelRead(
  channelId: number,
  body: MarkReadRequest,
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    `/chat/channels/${channelId}/read`,
    body,
  );
  return data.data!;
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
  const { data } = await apiClient.post<ApiResponse<QAThreadResponse>>(
    '/chat/qa/ask',
    body,
  );
  return data.data!;
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
  const { data } = await apiClient.get<ApiResponse<QAThreadResponse[]>>(
    '/chat/qa/threads',
    { params },
  );
  return data.data!;
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
  const { data } = await apiClient.post<ApiResponse<QAThreadResponse>>(
    `/chat/qa/threads/${threadId}/answer`,
    body,
  );
  return data.data!;
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
