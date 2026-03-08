/**
 * ChatMessageBubble — renders a single chat message.
 *
 * Handles text, photo, system messages, Q&A messages, replies,
 * edit/pin indicators, and long-press context actions.
 */

import { useState } from 'react';
import {
  Reply,
  Pin,
  PinOff,
  Pencil,
  Trash2,
  CornerUpRight,
  AlertCircle,
} from 'lucide-react';
import type { ChatMessageResponse } from '../../../lib/types';

interface ChatMessageBubbleProps {
  message: ChatMessageResponse;
  isOwn: boolean;
  onReply?: (message: ChatMessageResponse) => void;
  onEdit?: (message: ChatMessageResponse) => void;
  onDelete?: (messageId: number) => void;
  onPin?: (messageId: number) => void;
  onUnpin?: (messageId: number) => void;
}

const SYSTEM_TYPES = new Set(['system', 'qa_question', 'qa_answer', 'qa_escalation']);

export function ChatMessageBubble({
  message,
  isOwn,
  onReply,
  onEdit,
  onDelete,
  onPin,
  onUnpin,
}: ChatMessageBubbleProps) {
  const [showActions, setShowActions] = useState(false);

  // System messages render as centered banners
  if (SYSTEM_TYPES.has(message.message_type)) {
    return (
      <div className="flex justify-center my-2">
        <div className="bg-surface-secondary text-gray-500 dark:text-gray-400 text-xs px-3 py-1.5 rounded-full max-w-[80%] text-center">
          {message.message_type === 'qa_question' && (
            <span className="font-medium text-amber-600 dark:text-amber-400">Q: </span>
          )}
          {message.message_type === 'qa_answer' && (
            <span className="font-medium text-green-600 dark:text-green-400">A: </span>
          )}
          {message.message_type === 'qa_escalation' && (
            <AlertCircle className="h-3 w-3 inline mr-1 text-orange-500" />
          )}
          {message.sender_name && (
            <span className="font-medium">{message.sender_name}: </span>
          )}
          {message.content}
        </div>
      </div>
    );
  }

  const time = message.created_at
    ? new Date(message.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : '';

  return (
    <div
      className={`group flex ${isOwn ? 'justify-end' : 'justify-start'} mb-1`}
      onMouseEnter={() => setShowActions(true)}
      onMouseLeave={() => setShowActions(false)}
    >
      <div className={`max-w-[75%] ${isOwn ? 'order-1' : ''}`}>
        {/* Sender name (only for others in group chats) */}
        {!isOwn && message.sender_name && (
          <p className="text-xs font-medium text-primary-600 dark:text-primary-400 mb-0.5 px-1">
            {message.sender_name}
          </p>
        )}

        {/* Reply preview */}
        {message.reply_to_id && message.reply_preview && (
          <div className={`flex items-start gap-1 px-3 pt-2 pb-0 rounded-t-lg ${
            isOwn
              ? 'bg-primary-600 dark:bg-primary-700'
              : 'bg-gray-100 dark:bg-gray-700'
          }`}>
            <CornerUpRight className={`h-3 w-3 mt-0.5 flex-shrink-0 ${
              isOwn ? 'text-primary-300' : 'text-gray-400'
            }`} />
            <p className={`text-xs truncate ${
              isOwn ? 'text-primary-200' : 'text-gray-500 dark:text-gray-400'
            }`}>
              <span className="font-medium">{message.reply_sender_name}: </span>
              {message.reply_preview}
            </p>
          </div>
        )}

        {/* Message bubble */}
        <div className={`px-3 py-2 ${
          message.reply_to_id ? 'rounded-b-lg' : 'rounded-lg'
        } ${
          isOwn
            ? 'bg-primary-600 dark:bg-primary-700 text-white'
            : 'bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-gray-100'
        }`}>
          {/* Photo attachment */}
          {message.message_type === 'photo' && message.media_path && (
            <img
              src={message.media_path}
              alt="Shared photo"
              className="rounded max-w-full max-h-64 mb-1 cursor-pointer"
              loading="lazy"
            />
          )}

          {/* Text content */}
          {message.content && (
            <p className="text-sm whitespace-pre-wrap break-words">
              {message.content}
            </p>
          )}

          {/* Footer: time + edited + pinned */}
          <div className={`flex items-center gap-1.5 mt-1 ${
            isOwn ? 'justify-end' : 'justify-start'
          }`}>
            {message.pinned_at && (
              <Pin className={`h-3 w-3 ${isOwn ? 'text-primary-300' : 'text-gray-400'}`} />
            )}
            {message.edited_at && (
              <span className={`text-[10px] italic ${
                isOwn ? 'text-primary-300' : 'text-gray-400 dark:text-gray-500'
              }`}>edited</span>
            )}
            <span className={`text-[10px] ${
              isOwn ? 'text-primary-300' : 'text-gray-400 dark:text-gray-500'
            }`}>{time}</span>
          </div>
        </div>
      </div>

      {/* Hover actions */}
      {showActions && (
        <div className={`flex items-center gap-0.5 mx-1 ${isOwn ? 'order-0' : 'order-2'}`}>
          {onReply && (
            <button
              onClick={() => onReply(message)}
              className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
              title="Reply"
            >
              <Reply className="h-3.5 w-3.5 text-gray-400" />
            </button>
          )}
          {isOwn && onEdit && (
            <button
              onClick={() => onEdit(message)}
              className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
              title="Edit"
            >
              <Pencil className="h-3.5 w-3.5 text-gray-400" />
            </button>
          )}
          {message.pinned_at ? (
            onUnpin && (
              <button
                onClick={() => onUnpin(message.id)}
                className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
                title="Unpin"
              >
                <PinOff className="h-3.5 w-3.5 text-gray-400" />
              </button>
            )
          ) : (
            onPin && (
              <button
                onClick={() => onPin(message.id)}
                className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
                title="Pin"
              >
                <Pin className="h-3.5 w-3.5 text-gray-400" />
              </button>
            )
          )}
          {isOwn && onDelete && (
            <button
              onClick={() => onDelete(message.id)}
              className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
              title="Delete"
            >
              <Trash2 className="h-3.5 w-3.5 text-red-400" />
            </button>
          )}
        </div>
      )}
    </div>
  );
}
