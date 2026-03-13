/**
 * ChatChannelList — left panel showing user's channels with unread badges.
 *
 * Features:
 * - Search/filter channels by name
 * - Unread count badges
 * - Last message preview
 * - Channel type icons (job vs DM)
 * - New DM button
 */

import { useState, useMemo } from 'react';
import { Search, MessageSquare, Briefcase, Plus, Users } from 'lucide-react';
import type { ChatChannelResponse } from '../../../lib/types';

interface ChatChannelListProps {
  channels: ChatChannelResponse[];
  selectedId: number | null;
  onSelect: (channelId: number) => void;
  onNewDM?: () => void;
  totalUnread: number;
  unreadMentions: number;
}

export function ChatChannelList({
  channels,
  selectedId,
  onSelect,
  onNewDM,
  totalUnread,
  unreadMentions,
}: ChatChannelListProps) {
  const [search, setSearch] = useState('');

  const filtered = useMemo(() => {
    if (!search.trim()) return channels;
    const q = search.toLowerCase();
    return channels.filter((ch) => {
      const name = getChannelDisplayName(ch).toLowerCase();
      return name.includes(q);
    });
  }, [channels, search]);

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="p-4 border-b border-border">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              Messages
            </h2>
            {totalUnread > 0 && (
              <span className="bg-primary-600 text-white text-xs font-bold px-2 py-0.5 rounded-full">
                {totalUnread > 99 ? '99+' : totalUnread}
              </span>
            )}
          </div>
          {onNewDM && (
            <button
              onClick={onNewDM}
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"
              title="New message"
            >
              <Plus className="h-5 w-5 text-gray-500 dark:text-gray-400" />
            </button>
          )}
        </div>

        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search channels..."
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-border bg-surface-secondary text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500"
          />
        </div>

        {/* Mentions badge */}
        {unreadMentions > 0 && (
          <div className="flex items-center gap-2 mt-2 px-2 py-1.5 bg-amber-50 dark:bg-amber-950/30 rounded-lg text-xs text-amber-700 dark:text-amber-400">
            <span className="font-bold">@</span>
            {unreadMentions} unread mention{unreadMentions !== 1 && 's'}
          </div>
        )}
      </div>

      {/* Channel list */}
      <div className="flex-1 overflow-y-auto">
        {filtered.length === 0 ? (
          <div className="text-center py-8 text-sm text-gray-400">
            {search ? 'No matching channels' : 'No conversations yet'}
          </div>
        ) : (
          filtered.map((ch) => (
            <ChannelRow
              key={ch.id}
              channel={ch}
              isSelected={ch.id === selectedId}
              onSelect={() => onSelect(ch.id)}
            />
          ))
        )}
      </div>
    </div>
  );
}


// ── Channel Row ────────────────────────────────────────────────────

function ChannelRow({
  channel,
  isSelected,
  onSelect,
}: {
  channel: ChatChannelResponse;
  isSelected: boolean;
  onSelect: () => void;
}) {
  const displayName = getChannelDisplayName(channel);
  const lastMsg = channel.last_message;
  const hasUnread = channel.unread_count > 0;

  const time = lastMsg?.created_at
    ? formatRelativeTime(lastMsg.created_at)
    : '';

  return (
    <button
      onClick={onSelect}
      className={`w-full flex items-start gap-3 px-4 py-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors ${
        isSelected
          ? 'bg-primary-50 dark:bg-primary-950/30 border-r-2 border-primary-500'
          : ''
      }`}
    >
      {/* Channel icon */}
      <div className={`flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center ${
        channel.channel_type === 'job'
          ? 'bg-blue-100 dark:bg-blue-900/50'
          : 'bg-gray-100 dark:bg-gray-700'
      }`}>
        {channel.channel_type === 'job' ? (
          <Briefcase className="h-5 w-5 text-blue-600 dark:text-blue-400" />
        ) : channel.member_count > 2 ? (
          <Users className="h-5 w-5 text-gray-500 dark:text-gray-400" />
        ) : (
          <MessageSquare className="h-5 w-5 text-gray-500 dark:text-gray-400" />
        )}
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between">
          <p className={`text-sm truncate ${
            hasUnread
              ? 'font-semibold text-gray-900 dark:text-gray-100'
              : 'font-medium text-gray-700 dark:text-gray-300'
          }`}>
            {displayName}
          </p>
          <span className="text-[10px] text-gray-400 flex-shrink-0 ml-2">
            {time}
          </span>
        </div>

        <div className="flex items-center justify-between mt-0.5">
          <p className={`text-xs truncate ${
            hasUnread
              ? 'text-gray-700 dark:text-gray-300'
              : 'text-gray-400 dark:text-gray-500'
          }`}>
            {lastMsg
              ? `${lastMsg.sender_name}: ${lastMsg.content || '📷 Photo'}`
              : 'No messages yet'}
          </p>
          {hasUnread && (
            <span className="bg-primary-600 text-white text-[10px] font-bold min-w-[18px] h-[18px] flex items-center justify-center rounded-full px-1 ml-2 flex-shrink-0">
              {channel.unread_count > 99 ? '99+' : channel.unread_count}
            </span>
          )}
        </div>
      </div>
    </button>
  );
}


// ── Helpers ─────────────────────────────────────────────────────────

function getChannelDisplayName(channel: ChatChannelResponse): string {
  if (channel.channel_type === 'job') {
    return channel.job_number
      ? `${channel.job_number} – ${channel.job_name || 'Job'}`
      : channel.name || 'Job Chat';
  }
  return channel.name || 'Direct Message';
}

function formatRelativeTime(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);

  if (diffMins < 1) return 'now';
  if (diffMins < 60) return `${diffMins}m`;

  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h`;

  const diffDays = Math.floor(diffHours / 24);
  if (diffDays < 7) return `${diffDays}d`;

  return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
}
