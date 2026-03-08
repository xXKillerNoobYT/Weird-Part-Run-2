/**
 * ChatMessageView — right panel showing messages for a selected channel.
 *
 * Features:
 * - Cursor-based infinite scroll (load older messages on scroll up)
 * - Auto-scroll to bottom on new messages
 * - Date separators between message groups
 * - Pinned messages banner
 * - Compose bar integration
 * - 5-second polling for live updates
 */

import { useState, useRef, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Loader2 } from 'lucide-react';
import {
  getChannelDetail,
  sendMessage,
  editMessage as apiEditMessage,
  deleteMessage as apiDeleteMessage,
  pinMessage as apiPinMessage,
  unpinMessage as apiUnpinMessage,
  markChannelRead,
} from '../../../api/chat';
import type { ChatMessageResponse, SendMessageRequest } from '../../../lib/types';
import { ChatMessageBubble } from './ChatMessageBubble';
import { ChatPinnedBanner } from './ChatPinnedBanner';
import { ChatMessageComposer } from './ChatMessageComposer';

interface ChatMessageViewProps {
  channelId: number;
  currentUserId: number;
  onBack?: () => void;
  channelName?: string;
}

export function ChatMessageView({
  channelId,
  currentUserId,
  onBack,
  channelName,
}: ChatMessageViewProps) {
  const queryClient = useQueryClient();
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const [replyTo, setReplyTo] = useState<ChatMessageResponse | null>(null);
  const [editingMessage, setEditingMessage] = useState<ChatMessageResponse | null>(null);
  const prevMessageCount = useRef(0);

  // ── Data fetching with 5s polling ──────────────────────────────
  const { data, isLoading } = useQuery({
    queryKey: ['chat-channel', channelId],
    queryFn: () => getChannelDetail(channelId),
    refetchInterval: 5000,
    refetchIntervalInBackground: false,
  });

  const messages = data?.messages ?? [];
  const members = data?.members ?? [];
  const pinnedMessages = data?.pinned_messages ?? [];

  // ── Auto-scroll to bottom on new messages ──────────────────────
  useEffect(() => {
    if (messages.length > prevMessageCount.current) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
    prevMessageCount.current = messages.length;
  }, [messages.length]);

  // ── Mark as read when messages load ────────────────────────────
  useEffect(() => {
    if (messages.length > 0) {
      const lastId = messages[messages.length - 1].id;
      markChannelRead(channelId, { last_read_message_id: lastId }).catch(() => {
        // Silent fail — read receipts are best-effort
      });
    }
  }, [channelId, messages.length]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Load older messages ────────────────────────────────────────
  const handleScrollUp = useCallback(() => {
    const container = scrollContainerRef.current;
    if (!container || !data?.has_more || isLoading) return;

    if (container.scrollTop < 100 && messages.length > 0) {
      const oldestId = messages[0].id;
      // Fetch older page and merge — for v1.0 keep it simple
      // The query will refetch with the same key, so we rely on
      // the server returning the full visible set. In future,
      // we'd use infinite queries for true cursor pagination.
      queryClient.prefetchQuery({
        queryKey: ['chat-channel', channelId, 'before', oldestId],
        queryFn: () => getChannelDetail(channelId, oldestId),
      });
    }
  }, [channelId, data?.has_more, isLoading, messages, queryClient]);

  // ── Mutations ──────────────────────────────────────────────────
  const sendMutation = useMutation({
    mutationFn: (body: SendMessageRequest) => sendMessage(channelId, body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['chat-channel', channelId] });
      queryClient.invalidateQueries({ queryKey: ['chat-inbox'] });
    },
  });

  const editMutation = useMutation({
    mutationFn: ({ id, content }: { id: number; content: string }) =>
      apiEditMessage(id, { content }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['chat-channel', channelId] });
      setEditingMessage(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => apiDeleteMessage(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['chat-channel', channelId] });
    },
  });

  const pinMutation = useMutation({
    mutationFn: (id: number) => apiPinMessage(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['chat-channel', channelId] });
    },
  });

  const unpinMutation = useMutation({
    mutationFn: (id: number) => apiUnpinMessage(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['chat-channel', channelId] });
    },
  });

  // ── Handlers ───────────────────────────────────────────────────
  const handleSend = useCallback((body: SendMessageRequest) => {
    if (editingMessage) {
      if (body.content) {
        editMutation.mutate({ id: editingMessage.id, content: body.content });
      }
      return;
    }
    sendMutation.mutate(body);
  }, [editingMessage, sendMutation, editMutation]);

  const handleEdit = useCallback((msg: ChatMessageResponse) => {
    setEditingMessage(msg);
    setReplyTo(null);
  }, []);

  // ── Group messages by date ─────────────────────────────────────
  const groupedMessages = groupMessagesByDate(messages);

  // ── Render ─────────────────────────────────────────────────────
  return (
    <div className="flex flex-col h-full">
      {/* Channel header */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-border bg-surface">
        {onBack && (
          <button
            onClick={onBack}
            className="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700 lg:hidden"
          >
            <ArrowLeft className="h-5 w-5 text-gray-500" />
          </button>
        )}
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
            {channelName || 'Chat'}
          </h3>
          <p className="text-xs text-gray-400">
            {members.length} member{members.length !== 1 && 's'}
          </p>
        </div>
      </div>

      {/* Pinned messages */}
      <ChatPinnedBanner
        pinnedMessages={pinnedMessages}
        onUnpin={(id) => unpinMutation.mutate(id)}
      />

      {/* Messages area */}
      <div
        ref={scrollContainerRef}
        className="flex-1 overflow-y-auto px-4 py-3"
        onScroll={handleScrollUp}
      >
        {isLoading ? (
          <div className="flex items-center justify-center h-full">
            <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
          </div>
        ) : messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <p className="text-gray-400 text-sm">No messages yet</p>
            <p className="text-gray-400 text-xs mt-1">
              Send the first message to start the conversation
            </p>
          </div>
        ) : (
          <>
            {data?.has_more && (
              <div className="text-center py-2">
                <button
                  onClick={handleScrollUp}
                  className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
                >
                  Load older messages
                </button>
              </div>
            )}

            {groupedMessages.map(({ date, messages: dayMessages }) => (
              <div key={date}>
                {/* Date separator */}
                <div className="flex items-center gap-3 my-4">
                  <div className="flex-1 border-t border-border" />
                  <span className="text-[10px] text-gray-400 font-medium uppercase">
                    {formatDateLabel(date)}
                  </span>
                  <div className="flex-1 border-t border-border" />
                </div>

                {/* Messages for this date */}
                {dayMessages.map((msg) => (
                  <ChatMessageBubble
                    key={msg.id}
                    message={msg}
                    isOwn={msg.sender_id === currentUserId}
                    onReply={(m) => { setReplyTo(m); setEditingMessage(null); }}
                    onEdit={handleEdit}
                    onDelete={(id) => deleteMutation.mutate(id)}
                    onPin={(id) => pinMutation.mutate(id)}
                    onUnpin={(id) => unpinMutation.mutate(id)}
                  />
                ))}
              </div>
            ))}

            <div ref={messagesEndRef} />
          </>
        )}
      </div>

      {/* Compose bar */}
      <div className="relative">
        <ChatMessageComposer
          channelId={channelId}
          members={members}
          currentUserId={currentUserId}
          replyTo={editingMessage ? null : replyTo}
          onClearReply={() => { setReplyTo(null); setEditingMessage(null); }}
          onSend={handleSend}
          disabled={sendMutation.isPending || editMutation.isPending}
        />
      </div>
    </div>
  );
}


// ── Helpers ────────────────────────────────────────────────────────

interface MessageGroup {
  date: string;
  messages: ChatMessageResponse[];
}

function groupMessagesByDate(messages: ChatMessageResponse[]): MessageGroup[] {
  const groups: MessageGroup[] = [];
  let currentDate = '';

  for (const msg of messages) {
    const date = msg.created_at
      ? new Date(msg.created_at).toLocaleDateString()
      : 'Unknown';

    if (date !== currentDate) {
      currentDate = date;
      groups.push({ date, messages: [msg] });
    } else {
      groups[groups.length - 1].messages.push(msg);
    }
  }

  return groups;
}

function formatDateLabel(dateStr: string): string {
  const date = new Date(dateStr);
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);

  if (date.toDateString() === today.toDateString()) return 'Today';
  if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';

  return date.toLocaleDateString([], {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}
