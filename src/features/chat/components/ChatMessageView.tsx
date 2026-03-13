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
 * - Optimistic pending indicators for sent messages
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

  // ── Infinite scroll: accumulated older messages ────────────────
  const [olderMessages, setOlderMessages] = useState<ChatMessageResponse[]>([]);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [hasMoreOlder, setHasMoreOlder] = useState(true);
  const loadingOlderRef = useRef(false);

  // ── Pending message tracking ───────────────────────────────────
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());
  const pendingIdCounter = useRef(0);

  // Reset older messages when channel changes
  useEffect(() => {
    setOlderMessages([]);
    setHasMoreOlder(true);
    prevMessageCount.current = 0;
    setPendingIds(new Set());
  }, [channelId]);

  // ── Data fetching with 5s polling ──────────────────────────────
  const { data, isLoading } = useQuery({
    queryKey: ['chat-channel', channelId],
    queryFn: () => getChannelDetail(channelId),
    refetchInterval: 5000,
    refetchIntervalInBackground: false,
  });

  const latestMessages = data?.messages ?? [];
  const members = data?.members ?? [];
  const pinnedMessages = data?.pinned_messages ?? [];

  // Merge older pages with latest page, deduplicating by ID
  const allMessages = deduplicateMessages([...olderMessages, ...latestMessages]);

  // Clear pending IDs that now appear in server data
  useEffect(() => {
    if (pendingIds.size === 0) return;
    // Once server poll confirms messages, pending IDs are no longer needed.
    // We clear them when message count grows (server confirmed new data).
    if (latestMessages.length > prevMessageCount.current && prevMessageCount.current > 0) {
      setPendingIds(new Set());
    }
  }, [latestMessages.length]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Auto-scroll to bottom on new messages ──────────────────────
  useEffect(() => {
    if (allMessages.length > prevMessageCount.current) {
      // Only auto-scroll if user is near the bottom
      const container = scrollContainerRef.current;
      if (container) {
        const isNearBottom = container.scrollHeight - container.scrollTop - container.clientHeight < 150;
        if (isNearBottom || prevMessageCount.current === 0) {
          messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
        }
      }
    }
    prevMessageCount.current = allMessages.length;
  }, [allMessages.length]);

  // ── Mark as read when messages load ────────────────────────────
  useEffect(() => {
    if (latestMessages.length > 0) {
      const lastId = latestMessages[latestMessages.length - 1].id;
      markChannelRead(channelId, { last_read_message_id: lastId }).catch(() => {
        // Silent fail — read receipts are best-effort
      });
    }
  }, [channelId, latestMessages.length]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Load older messages (true cursor pagination) ───────────────
  const loadOlderMessages = useCallback(async () => {
    if (loadingOlderRef.current || !hasMoreOlder || allMessages.length === 0) return;
    loadingOlderRef.current = true;
    setLoadingOlder(true);

    try {
      const oldestId = allMessages[0].id;
      const olderPage = await getChannelDetail(channelId, oldestId);

      if (olderPage.messages.length === 0) {
        setHasMoreOlder(false);
      } else {
        // Preserve scroll position — measure before prepending
        const container = scrollContainerRef.current;
        const prevScrollHeight = container?.scrollHeight ?? 0;

        setOlderMessages((prev) =>
          deduplicateMessages([...olderPage.messages, ...prev]),
        );
        setHasMoreOlder(olderPage.has_more ?? false);

        // After React re-renders, restore scroll position
        requestAnimationFrame(() => {
          if (container) {
            const newScrollHeight = container.scrollHeight;
            container.scrollTop += newScrollHeight - prevScrollHeight;
          }
        });
      }
    } catch {
      // Network error — don't break the experience
    } finally {
      setLoadingOlder(false);
      loadingOlderRef.current = false;
    }
  }, [channelId, hasMoreOlder, allMessages]);

  const handleScroll = useCallback(() => {
    const container = scrollContainerRef.current;
    if (!container) return;

    // Trigger load when scrolled near the top
    if (container.scrollTop < 80) {
      loadOlderMessages();
    }
  }, [loadOlderMessages]);

  // ── Mutations ──────────────────────────────────────────────────
  const sendMutation = useMutation({
    mutationFn: (body: SendMessageRequest) => sendMessage(channelId, body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['chat-channel', channelId] });
      queryClient.invalidateQueries({ queryKey: ['chat-inbox'] });
      queryClient.invalidateQueries({ queryKey: ['chat-badge'] });
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

    // Add a pending message ID for optimistic UI
    const tempId = `pending-${++pendingIdCounter.current}`;
    setPendingIds((prev) => new Set(prev).add(tempId));

    sendMutation.mutate(body, {
      onSettled: () => {
        // Remove this pending ID regardless of success/failure
        setPendingIds((prev) => {
          const next = new Set(prev);
          next.delete(tempId);
          return next;
        });
      },
    });
  }, [editingMessage, sendMutation, editMutation]);

  const handleEdit = useCallback((msg: ChatMessageResponse) => {
    setEditingMessage(msg);
    setReplyTo(null);
  }, []);

  // ── Group messages by date ─────────────────────────────────────
  const groupedMessages = groupMessagesByDate(allMessages);

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
        onScroll={handleScroll}
      >
        {isLoading && allMessages.length === 0 ? (
          <div className="flex items-center justify-center h-full">
            <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
          </div>
        ) : allMessages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <p className="text-gray-400 text-sm">No messages yet</p>
            <p className="text-gray-400 text-xs mt-1">
              Send the first message to start the conversation
            </p>
          </div>
        ) : (
          <>
            {/* Loading older indicator */}
            {loadingOlder && (
              <div className="flex items-center justify-center py-3">
                <Loader2 className="h-4 w-4 animate-spin text-gray-400 mr-2" />
                <span className="text-xs text-gray-400">Loading older messages...</span>
              </div>
            )}

            {hasMoreOlder && !loadingOlder && (
              <div className="text-center py-2">
                <button
                  onClick={loadOlderMessages}
                  className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
                >
                  Load older messages
                </button>
              </div>
            )}

            {!hasMoreOlder && allMessages.length > 0 && (
              <div className="text-center py-2">
                <span className="text-[10px] text-gray-400">Beginning of conversation</span>
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

            {/* Pending message indicators */}
            {pendingIds.size > 0 && (
              <div className="mb-1">
                {Array.from(pendingIds).map((pid) => (
                  <ChatMessageBubble
                    key={pid}
                    message={{
                      id: -1,
                      channel_id: channelId,
                      sender_id: currentUserId,
                      sender_name: 'You',
                      message_type: 'text',
                      content: 'Sending...',
                      created_at: new Date().toISOString(),
                    } as ChatMessageResponse}
                    isOwn
                    isPending
                  />
                ))}
              </div>
            )}

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

/** Deduplicate messages by ID, preserving order (newest last). */
function deduplicateMessages(messages: ChatMessageResponse[]): ChatMessageResponse[] {
  const seen = new Set<number>();
  const result: ChatMessageResponse[] = [];

  for (const msg of messages) {
    if (!seen.has(msg.id)) {
      seen.add(msg.id);
      result.push(msg);
    }
  }

  // Sort by ID ascending (chronological order)
  return result.sort((a, b) => a.id - b.id);
}
