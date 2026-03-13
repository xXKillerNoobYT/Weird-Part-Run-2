/**
 * ChatPinnedBanner — collapsible banner showing pinned messages.
 *
 * Shows a compact "N pinned messages" bar that expands to reveal
 * the full list of pinned messages with unpin actions.
 */

import { useState } from 'react';
import { Pin, ChevronDown, ChevronUp, X } from 'lucide-react';
import type { ChatMessageResponse } from '../../../lib/types';

interface ChatPinnedBannerProps {
  pinnedMessages: ChatMessageResponse[];
  onUnpin?: (messageId: number) => void;
  onJumpTo?: (messageId: number) => void;
}

export function ChatPinnedBanner({
  pinnedMessages,
  onUnpin,
  onJumpTo,
}: ChatPinnedBannerProps) {
  const [expanded, setExpanded] = useState(false);

  if (pinnedMessages.length === 0) return null;

  return (
    <div className="border-b border-border bg-amber-50 dark:bg-amber-950/30">
      {/* Collapsed bar */}
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex items-center justify-between w-full px-4 py-2 text-sm hover:bg-amber-100 dark:hover:bg-amber-950/50 transition-colors"
      >
        <div className="flex items-center gap-2 text-amber-700 dark:text-amber-400">
          <Pin className="h-3.5 w-3.5" />
          <span className="font-medium">
            {pinnedMessages.length} pinned message{pinnedMessages.length !== 1 && 's'}
          </span>
        </div>
        {expanded ? (
          <ChevronUp className="h-4 w-4 text-amber-600 dark:text-amber-400" />
        ) : (
          <ChevronDown className="h-4 w-4 text-amber-600 dark:text-amber-400" />
        )}
      </button>

      {/* Expanded list */}
      {expanded && (
        <div className="px-4 pb-2 space-y-2 max-h-48 overflow-y-auto">
          {pinnedMessages.map((msg) => (
            <div
              key={msg.id}
              className="flex items-start justify-between gap-2 p-2 rounded bg-white dark:bg-gray-800 text-sm"
            >
              <button
                onClick={() => onJumpTo?.(msg.id)}
                className="flex-1 text-left hover:text-primary-600 dark:hover:text-primary-400"
              >
                <p className="text-xs font-medium text-gray-500 dark:text-gray-400">
                  {msg.sender_name}
                </p>
                <p className="text-gray-700 dark:text-gray-300 line-clamp-2">
                  {msg.content || '📷 Photo'}
                </p>
              </button>
              {onUnpin && (
                <button
                  onClick={() => onUnpin(msg.id)}
                  className="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700 flex-shrink-0"
                  title="Unpin"
                >
                  <X className="h-3.5 w-3.5 text-gray-400" />
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
