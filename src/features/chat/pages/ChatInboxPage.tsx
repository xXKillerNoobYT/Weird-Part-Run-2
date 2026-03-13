/**
 * ChatInboxPage — two-panel master-detail chat view.
 *
 * Layout:
 * - Desktop/Tablet: side-by-side (300px channel list + flex-1 message view)
 * - Mobile: single panel — show either channel list OR message view
 *
 * Polling: channel list refreshes every 30s via TanStack Query.
 * The message view handles its own 5s polling internally.
 */

import { useState, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { MessageSquare } from 'lucide-react';
import { ErrorFallback } from '../../../components/ui/ErrorFallback';
import { useAuthStore } from '../../../stores/auth-store';
import { getInbox } from '../../../api/chat';
import { ChatChannelList } from '../components/ChatChannelList';
import { ChatMessageView } from '../components/ChatMessageView';

export default function ChatInboxPage() {
  const { user } = useAuthStore();
  const [selectedChannelId, setSelectedChannelId] = useState<number | null>(null);

  // ── Inbox data (30s polling for badge/preview updates) ─────────
  const { data: inbox, isError, refetch } = useQuery({
    queryKey: ['chat-inbox'],
    queryFn: getInbox,
    refetchInterval: 30_000,
    refetchIntervalInBackground: false,
  });

  const channels = inbox?.channels ?? [];

  // Find the selected channel's display name for the header
  const selectedChannel = channels.find((c) => c.id === selectedChannelId);
  const selectedChannelName = selectedChannel
    ? selectedChannel.channel_type === 'job' && selectedChannel.job_number
      ? `${selectedChannel.job_number} – ${selectedChannel.job_name || 'Job Chat'}`
      : selectedChannel.name || 'Chat'
    : undefined;

  // ── Navigation ─────────────────────────────────────────────────
  const handleSelectChannel = useCallback((channelId: number) => {
    setSelectedChannelId(channelId);
  }, []);

  const handleBack = useCallback(() => {
    setSelectedChannelId(null);
  }, []);

  if (!user) return null;
  if (isError) return <ErrorFallback message="Failed to load chat inbox" onRetry={refetch} />;

  // ── Render ─────────────────────────────────────────────────────
  return (
    <div className="h-full flex flex-col">
      {/* Two-panel layout */}
      <div className="flex-1 flex overflow-hidden">
        {/* Channel list — always visible on lg+, hidden on mobile when a channel is selected */}
        <div
          className={`w-full lg:w-[300px] xl:w-[340px] lg:flex-shrink-0 border-r border-border ${selectedChannelId != null ? 'hidden lg:flex lg:flex-col' : 'flex flex-col'
            }`}
        >
          <ChatChannelList
            channels={channels}
            selectedId={selectedChannelId}
            onSelect={handleSelectChannel}
            totalUnread={inbox?.total_unread ?? 0}
            unreadMentions={inbox?.unread_mentions ?? 0}
          />
        </div>

        {/* Message view — always visible on lg+ when selected, full-screen on mobile */}
        <div
          className={`flex-1 min-w-0 ${selectedChannelId != null ? 'flex flex-col' : 'hidden lg:flex lg:flex-col'
            }`}
        >
          {selectedChannelId != null ? (
            <ChatMessageView
              channelId={selectedChannelId}
              currentUserId={user.id}
              onBack={handleBack}
              channelName={selectedChannelName}
            />
          ) : (
            /* Empty state — visible on desktop when no channel selected */
            <div className="flex-1 flex flex-col items-center justify-center text-center px-6">
              <div className="w-16 h-16 rounded-full bg-gray-100 dark:bg-gray-800 flex items-center justify-center mb-4">
                <MessageSquare className="h-8 w-8 text-gray-400" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1">
                Select a conversation
              </h3>
              <p className="text-sm text-gray-500 dark:text-gray-400 max-w-xs">
                Choose a channel from the list to start chatting, or create a new direct message.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
