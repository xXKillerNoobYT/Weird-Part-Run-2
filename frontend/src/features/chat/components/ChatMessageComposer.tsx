/**
 * ChatMessageComposer — compose bar for sending messages.
 *
 * Features:
 * - Auto-growing textarea
 * - @mention autocomplete (dropdown matching channel members)
 * - File attachment (photos, documents, audio, any file)
 * - Voice recording (MediaRecorder → webm/mp4)
 * - Reply-to indicator with dismiss
 * - Send on Enter (Shift+Enter for newline)
 */

import { useState, useRef, useCallback, useEffect } from 'react';
import { Send, Paperclip, X, AtSign, Mic, Square, Trash2, Play, Pause } from 'lucide-react';
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

  // ── Voice recording state ─────────────────────────────────
  const [isRecording, setIsRecording] = useState(false);
  const [recordingTime, setRecordingTime] = useState(0);
  const [voiceBlob, setVoiceBlob] = useState<Blob | null>(null);
  const [voiceUrl, setVoiceUrl] = useState<string | null>(null);
  const [isPlayingPreview, setIsPlayingPreview] = useState(false);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<ReturnType<typeof setInterval>>(undefined);
  const previewAudioRef = useRef<HTMLAudioElement | null>(null);

  // Clean up object URLs on unmount
  useEffect(() => {
    return () => {
      if (voiceUrl) URL.revokeObjectURL(voiceUrl);
      if (timerRef.current) clearInterval(timerRef.current);
      if (mediaRecorderRef.current?.state === 'recording') {
        mediaRecorderRef.current.stop();
      }
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

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

  // ── Voice recording ───────────────────────────────────────
  const startRecording = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      // Prefer webm; Safari falls back to mp4
      const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
        ? 'audio/webm;codecs=opus'
        : 'audio/mp4';
      const recorder = new MediaRecorder(stream, { mimeType });
      chunksRef.current = [];

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };

      recorder.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(chunksRef.current, { type: mimeType });
        const url = URL.createObjectURL(blob);
        setVoiceBlob(blob);
        setVoiceUrl(url);
        setIsRecording(false);
        if (timerRef.current) clearInterval(timerRef.current);
      };

      recorder.start(250); // Collect in 250ms chunks
      mediaRecorderRef.current = recorder;
      setIsRecording(true);
      setRecordingTime(0);
      setVoiceBlob(null);
      if (voiceUrl) URL.revokeObjectURL(voiceUrl);
      setVoiceUrl(null);

      timerRef.current = setInterval(() => {
        setRecordingTime((t) => t + 1);
      }, 1000);
    } catch {
      // Permission denied or no mic — silently fail
    }
  }, [voiceUrl]);

  const stopRecording = useCallback(() => {
    if (mediaRecorderRef.current?.state === 'recording') {
      mediaRecorderRef.current.stop();
    }
  }, []);

  const discardVoice = useCallback(() => {
    if (voiceUrl) URL.revokeObjectURL(voiceUrl);
    setVoiceBlob(null);
    setVoiceUrl(null);
    setRecordingTime(0);
    setIsPlayingPreview(false);
    if (previewAudioRef.current) {
      previewAudioRef.current.pause();
      previewAudioRef.current = null;
    }
  }, [voiceUrl]);

  const togglePreview = useCallback(() => {
    if (!voiceUrl) return;
    if (isPlayingPreview && previewAudioRef.current) {
      previewAudioRef.current.pause();
      setIsPlayingPreview(false);
    } else {
      const audio = new Audio(voiceUrl);
      audio.onended = () => setIsPlayingPreview(false);
      audio.play().catch(() => { });
      previewAudioRef.current = audio;
      setIsPlayingPreview(true);
    }
  }, [voiceUrl, isPlayingPreview]);

  const formatTime = (seconds: number) => {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  };

  // ── Detect message_type from file ─────────────────────────
  const detectMessageType = (file: File): 'photo' | 'voice' | 'file' => {
    if (file.type.startsWith('image/')) return 'photo';
    if (file.type.startsWith('audio/')) return 'voice';
    return 'file';
  };

  const handleSend = useCallback(() => {
    const content = text.trim();
    if (!content && !mediaFile && !voiceBlob) return;

    const body: SendMessageRequest = {};
    if (content) body.content = content;
    if (mentionIds.length > 0) body.mention_ids = mentionIds;
    if (replyTo) body.reply_to_id = replyTo.id;

    if (voiceBlob) {
      // Voice message takes priority
      body.message_type = 'voice';
      const ext = voiceBlob.type.includes('mp4') ? 'mp4' : 'webm';
      body.media_path = `voice_${Date.now()}.${ext}`;
      body.media_mime_type = voiceBlob.type;
      body.media_size_bytes = voiceBlob.size;
    } else if (mediaFile) {
      body.message_type = detectMessageType(mediaFile);
      body.media_path = mediaFile.name;
      body.media_mime_type = mediaFile.type;
      body.media_size_bytes = mediaFile.size;
    }

    onSend(body);
    setText('');
    setMentionIds([]);
    setMediaFile(null);
    setMentionSearch(null);
    discardVoice();
    onClearReply();

    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }
  }, [text, mentionIds, mediaFile, voiceBlob, replyTo, onSend, onClearReply, discardVoice, detectMessageType]);

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
          title="Attach file"
          disabled={isRecording || !!voiceBlob}
        >
          <Paperclip className="h-5 w-5 text-gray-400" />
        </button>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*,audio/*,.pdf,.doc,.docx,.xls,.xlsx,.csv,.txt,.zip,.rar"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) setMediaFile(file);
            e.target.value = '';
          }}
        />

        {/* Voice recording UI */}
        {isRecording ? (
          /* Active recording — red dot + timer + stop button */
          <div className="flex items-center gap-2 flex-1 px-3 py-2 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
            <span className="relative flex h-3 w-3">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
              <span className="relative inline-flex rounded-full h-3 w-3 bg-red-500" />
            </span>
            <span className="text-sm font-medium text-red-600 dark:text-red-400 tabular-nums">
              {formatTime(recordingTime)}
            </span>
            <span className="text-xs text-red-500 dark:text-red-400">Recording...</span>
            <div className="flex-1" />
            <button
              onClick={stopRecording}
              className="p-1.5 rounded-lg bg-red-500 text-white hover:bg-red-600"
              title="Stop recording"
            >
              <Square className="h-4 w-4" />
            </button>
          </div>
        ) : voiceBlob && voiceUrl ? (
          /* Voice preview — play/pause + duration + discard + send */
          <div className="flex items-center gap-2 flex-1 px-3 py-2 rounded-lg bg-primary-50 dark:bg-primary-900/20 border border-primary-200 dark:border-primary-800">
            <button
              onClick={togglePreview}
              className="p-1.5 rounded-full bg-primary-500 text-white hover:bg-primary-600"
              title={isPlayingPreview ? 'Pause' : 'Play'}
            >
              {isPlayingPreview ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
            </button>
            <span className="text-sm font-medium text-primary-600 dark:text-primary-400 tabular-nums">
              {formatTime(recordingTime)}
            </span>
            <span className="text-xs text-gray-500 dark:text-gray-400">Voice message</span>
            <div className="flex-1" />
            <button
              onClick={discardVoice}
              className="p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
              title="Discard"
            >
              <Trash2 className="h-4 w-4 text-red-400" />
            </button>
          </div>
        ) : (
          /* Normal text input + mic button */
          <>
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

            {/* Mic button — only show when no text/file */}
            {!text.trim() && !mediaFile && (
              <button
                onClick={startRecording}
                className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 flex-shrink-0"
                title="Record voice message"
                disabled={disabled}
              >
                <Mic className="h-5 w-5 text-gray-400" />
              </button>
            )}
          </>
        )}

        {/* Send button */}
        <button
          onClick={handleSend}
          disabled={disabled || (!text.trim() && !mediaFile && !voiceBlob)}
          className="p-2 rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-40 disabled:cursor-not-allowed flex-shrink-0"
          title="Send message"
        >
          <Send className="h-5 w-5" />
        </button>
      </div>
    </div>
  );
}
