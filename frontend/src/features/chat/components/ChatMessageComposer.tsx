/**
 * ChatMessageComposer — compose bar for sending messages.
 *
 * Features:
 * - Auto-growing textarea
 * - @mention autocomplete (dropdown matching channel members)
 * - Photo attachment (file input)
 * - Reply-to indicator with dismiss
 * - Send on Enter (Shift+Enter for newline)
 */

import { useState, useRef, useCallback, useEffect } from 'react';
import { Send, Paperclip, X, AtSign } from 'lucide-react';
import type { ChatChannelMember, ChatMessageResponse, SendMessageRequest } from '../../../lib/types';

interface ChatMessageComposerProps {
  channelId: number;
  members: ChatChannelMember[];
  currentUserId: number;
  replyTo: ChatMessageResponse | null;
  onClearReply: () => void;
  onSend: (body: SendMessageRequest) => void;
  disabled?: boolean;
}

export function ChatMessageComposer({
  members,
  currentUserId,
  replyTo,
  onClearReply,
  onSend,
  disabled,
}: ChatMessageComposerProps) {
  const [text, setText] = useState('');
  const [mentionSearch, setMentionSearch] = useState<string | null>(null);
  const [mentionIds, setMentionIds] = useState<number[]>([]);
  const [mediaFile, setMediaFile] = useState<File | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Auto-resize textarea
  useEffect(() => {
    const ta = textareaRef.current;
    if (ta) {
      ta.style.height = 'auto';
      ta.style.height = `${Math.min(ta.scrollHeight, 120)}px`;
    }
  }, [text]);

  // Filter mentionable members (exclude self)
  const mentionCandidates = members.filter(
    (m) => m.user_id !== currentUserId && m.display_name,
  );

  const filteredMentions = mentionSearch !== null
    ? mentionCandidates.filter((m) =>
        m.display_name?.toLowerCase().includes(mentionSearch.toLowerCase()),
      )
    : [];

  const handleTextChange = useCallback((value: string) => {
    setText(value);

    // Detect @mention trigger: look for @ followed by text at cursor
    const lastAt = value.lastIndexOf('@');
    if (lastAt >= 0) {
      const afterAt = value.slice(lastAt + 1);
      // Only trigger if @ is at start or preceded by whitespace
      if (lastAt === 0 || /\s/.test(value[lastAt - 1])) {
        // Only show dropdown if there's no space after the search term
        if (!afterAt.includes(' ')) {
          setMentionSearch(afterAt);
          return;
        }
      }
    }
    setMentionSearch(null);
  }, []);

  const insertMention = useCallback((member: ChatChannelMember) => {
    const lastAt = text.lastIndexOf('@');
    if (lastAt >= 0) {
      const before = text.slice(0, lastAt);
      setText(`${before}@${member.display_name} `);
    }
    if (!mentionIds.includes(member.user_id)) {
      setMentionIds((prev) => [...prev, member.user_id]);
    }
    setMentionSearch(null);
    textareaRef.current?.focus();
  }, [text, mentionIds]);

  const handleSend = useCallback(() => {
    const content = text.trim();
    if (!content && !mediaFile) return;

    const body: SendMessageRequest = {};
    if (content) body.content = content;
    if (mentionIds.length > 0) body.mention_ids = mentionIds;
    if (replyTo) body.reply_to_id = replyTo.id;

    if (mediaFile) {
      body.message_type = 'photo';
      // For v1.0, media_path will be set after upload — for now, use filename
      body.media_path = mediaFile.name;
      body.media_mime_type = mediaFile.type;
      body.media_size_bytes = mediaFile.size;
    }

    onSend(body);
    setText('');
    setMentionIds([]);
    setMediaFile(null);
    setMentionSearch(null);
    onClearReply();

    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }
  }, [text, mentionIds, mediaFile, replyTo, onSend, onClearReply]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
    // Close mention dropdown on Escape
    if (e.key === 'Escape' && mentionSearch !== null) {
      setMentionSearch(null);
    }
  }, [handleSend, mentionSearch]);

  return (
    <div className="border-t border-border bg-surface">
      {/* Reply-to indicator */}
      {replyTo && (
        <div className="flex items-center gap-2 px-4 py-2 bg-gray-50 dark:bg-gray-800 border-b border-border">
          <div className="flex-1 min-w-0">
            <p className="text-xs font-medium text-primary-600 dark:text-primary-400">
              Replying to {replyTo.sender_name}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
              {replyTo.content || '📷 Photo'}
            </p>
          </div>
          <button
            onClick={onClearReply}
            className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 flex-shrink-0"
          >
            <X className="h-4 w-4 text-gray-400" />
          </button>
        </div>
      )}

      {/* Media preview */}
      {mediaFile && (
        <div className="flex items-center gap-2 px-4 py-2 bg-gray-50 dark:bg-gray-800 border-b border-border">
          <Paperclip className="h-4 w-4 text-gray-400 flex-shrink-0" />
          <span className="text-sm text-gray-600 dark:text-gray-400 truncate flex-1">
            {mediaFile.name}
          </span>
          <button
            onClick={() => setMediaFile(null)}
            className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 flex-shrink-0"
          >
            <X className="h-4 w-4 text-gray-400" />
          </button>
        </div>
      )}

      {/* Mention dropdown */}
      {mentionSearch !== null && filteredMentions.length > 0 && (
        <div className="absolute bottom-full left-0 right-0 mb-1 mx-4 bg-surface border border-border rounded-lg shadow-lg max-h-40 overflow-y-auto z-10">
          {filteredMentions.slice(0, 8).map((m) => (
            <button
              key={m.user_id}
              onClick={() => insertMention(m)}
              className="flex items-center gap-2 w-full px-3 py-2 text-sm hover:bg-gray-100 dark:hover:bg-gray-700 text-left"
            >
              <AtSign className="h-3.5 w-3.5 text-primary-500 flex-shrink-0" />
              <span className="text-gray-900 dark:text-gray-100">{m.display_name}</span>
              {m.username && (
                <span className="text-gray-400 text-xs">@{m.username}</span>
              )}
            </button>
          ))}
        </div>
      )}

      {/* Input area */}
      <div className="flex items-end gap-2 p-3">
        {/* Attachment button */}
        <button
          onClick={() => fileInputRef.current?.click()}
          className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 flex-shrink-0"
          title="Attach photo"
        >
          <Paperclip className="h-5 w-5 text-gray-400" />
        </button>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) setMediaFile(file);
            e.target.value = '';
          }}
        />

        {/* Textarea */}
        <div className="flex-1 relative">
          <textarea
            ref={textareaRef}
            value={text}
            onChange={(e) => handleTextChange(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Type a message..."
            disabled={disabled}
            rows={1}
            className="w-full resize-none rounded-lg border border-border bg-surface-secondary px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500 disabled:opacity-50"
          />
        </div>

        {/* Send button */}
        <button
          onClick={handleSend}
          disabled={disabled || (!text.trim() && !mediaFile)}
          className="p-2 rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-40 disabled:cursor-not-allowed flex-shrink-0"
          title="Send message"
        >
          <Send className="h-5 w-5" />
        </button>
      </div>
    </div>
  );
}
