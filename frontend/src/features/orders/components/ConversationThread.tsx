/**
 * ConversationThread — CRM-style threaded conversation view for POs.
 *
 * Displays a chronological list of conversation entries (notes, calls,
 * email summaries, actions, system messages) with:
 *   - Color-coded entry types (blue/green/purple/amber/gray)
 *   - Follow-up flag with toggle
 *   - Relative timestamps ("2h ago")
 *   - Inline "Add entry" form at the bottom
 *   - Auto-scrolls to newest entries
 *
 * Used in:
 *   - POManagementTab (right panel on desktop, below on mobile)
 *   - PO detail pages
 *   - Supplier conversation views
 */

import { useState, useRef, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  MessageSquare,
  Phone,
  Mail,
  Zap,
  Bot,
  Flag,
  FlagOff,
  Send,
  Loader2,
  ChevronDown,
  AlertCircle,
} from 'lucide-react';
import {
  getPOConversation,
  getSupplierConversation,
  addPOConversationEntry,
  toggleConversationFollowUp,
} from '../../../api/orders';
import { formatRelativeTime } from '../../../lib/utils';
import { cn } from '../../../lib/utils';
import type {
  POConversationEntry,
  POConversationCreate,
  POConversationEntryType,
} from '../../../lib/types';


// ── Visual config per entry type ────────────────────────────────

interface EntryTypeConfig {
  icon: React.ElementType;
  label: string;
  /** Left border + icon color classes */
  borderColor: string;
  iconColor: string;
  bgColor: string;
}

const ENTRY_TYPE_CONFIG: Record<POConversationEntryType, EntryTypeConfig> = {
  note: {
    icon: MessageSquare,
    label: 'Note',
    borderColor: 'border-l-blue-400 dark:border-l-blue-500',
    iconColor: 'text-blue-500 dark:text-blue-400',
    bgColor: 'bg-blue-50/50 dark:bg-blue-900/10',
  },
  call: {
    icon: Phone,
    label: 'Call',
    borderColor: 'border-l-green-400 dark:border-l-green-500',
    iconColor: 'text-green-500 dark:text-green-400',
    bgColor: 'bg-green-50/50 dark:bg-green-900/10',
  },
  email_summary: {
    icon: Mail,
    label: 'Email',
    borderColor: 'border-l-purple-400 dark:border-l-purple-500',
    iconColor: 'text-purple-500 dark:text-purple-400',
    bgColor: 'bg-purple-50/50 dark:bg-purple-900/10',
  },
  action: {
    icon: Zap,
    label: 'Action',
    borderColor: 'border-l-amber-400 dark:border-l-amber-500',
    iconColor: 'text-amber-500 dark:text-amber-400',
    bgColor: 'bg-amber-50/50 dark:bg-amber-900/10',
  },
  system: {
    icon: Bot,
    label: 'System',
    borderColor: 'border-l-gray-300 dark:border-l-gray-600',
    iconColor: 'text-gray-400 dark:text-gray-500',
    bgColor: 'bg-gray-50/50 dark:bg-gray-800/30',
  },
};

/** Entry types the user can manually select (system is auto-generated) */
const MANUAL_ENTRY_TYPES: Exclude<POConversationEntryType, 'system'>[] = [
  'note',
  'call',
  'email_summary',
  'action',
];


// ── Props ───────────────────────────────────────────────────────

interface ConversationThreadProps {
  /** PO ID to load conversation for (mutually exclusive with supplierId) */
  poId?: number;
  /** Supplier ID to load cross-PO conversation (mutually exclusive with poId) */
  supplierId?: number;
  /** Whether the current user can add entries / toggle follow-ups */
  canEdit?: boolean;
  /** Max height for the scrollable area (CSS value) */
  maxHeight?: string;
  /** Additional className for the outer wrapper */
  className?: string;
}


// ── Single Entry Row ────────────────────────────────────────────

function ConversationEntry({
  entry,
  canEdit,
  onToggleFollowUp,
  isTogglingFollowUp,
}: {
  entry: POConversationEntry;
  canEdit: boolean;
  onToggleFollowUp: (entryId: number, resolved: boolean) => void;
  isTogglingFollowUp: boolean;
}) {
  const config = ENTRY_TYPE_CONFIG[entry.entry_type as POConversationEntryType] ?? ENTRY_TYPE_CONFIG.system;
  const Icon = config.icon;
  const hasUnresolvedFollowUp = entry.follow_up_needed && !entry.follow_up_resolved_at;

  return (
    <div
      className={cn(
        'border-l-3 pl-3 pr-3 py-2.5 rounded-r-lg transition-colors',
        config.borderColor,
        config.bgColor,
      )}
    >
      {/* ── Header row: icon + type + author + time ─────────── */}
      <div className="flex items-center gap-2 flex-wrap">
        <Icon className={cn('h-3.5 w-3.5 flex-shrink-0', config.iconColor)} />
        <span className={cn('text-[10px] font-semibold uppercase tracking-wider', config.iconColor)}>
          {config.label}
        </span>

        {/* PO number (shown in supplier-level threads) */}
        {entry.po_number && (
          <span className="text-[10px] text-gray-500 dark:text-gray-400 font-mono">
            PO-{entry.po_number}
          </span>
        )}

        <span className="flex-1" />

        {/* Follow-up flag */}
        {entry.follow_up_needed && (
          <button
            type="button"
            disabled={!canEdit || isTogglingFollowUp}
            onClick={() => onToggleFollowUp(entry.id, !entry.follow_up_resolved_at)}
            className={cn(
              'inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-medium transition-colors min-h-[28px]',
              hasUnresolvedFollowUp
                ? 'bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400 hover:bg-red-200 dark:hover:bg-red-900/50'
                : 'bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400 line-through',
            )}
            title={hasUnresolvedFollowUp ? 'Mark follow-up as resolved' : 'Reopen follow-up'}
          >
            {isTogglingFollowUp ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : hasUnresolvedFollowUp ? (
              <Flag className="h-3 w-3" />
            ) : (
              <FlagOff className="h-3 w-3" />
            )}
            {hasUnresolvedFollowUp ? 'Follow-up' : 'Resolved'}
          </button>
        )}

        {/* Timestamp */}
        <span className="text-[10px] text-gray-500 dark:text-gray-400 flex-shrink-0" title={entry.created_at ?? ''}>
          {formatRelativeTime(entry.created_at)}
        </span>
      </div>

      {/* ── Message body ────────────────────────────────────── */}
      <p className="text-sm text-gray-700 dark:text-gray-300 mt-1 whitespace-pre-wrap leading-relaxed">
        {entry.message}
      </p>

      {/* ── Footer: author name ─────────────────────────────── */}
      {entry.creator_name && (
        <p className="text-[10px] text-gray-500 dark:text-gray-400 mt-1">
          — {entry.creator_name}
        </p>
      )}
    </div>
  );
}


// ── Add Entry Form ──────────────────────────────────────────────

function AddEntryForm({
  poId,
  onSuccess,
}: {
  poId: number;
  onSuccess: () => void;
}) {
  const queryClient = useQueryClient();
  const [entryType, setEntryType] = useState<Exclude<POConversationEntryType, 'system'>>('note');
  const [message, setMessage] = useState('');
  const [followUpNeeded, setFollowUpNeeded] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const addMutation = useMutation({
    mutationFn: (body: POConversationCreate) => addPOConversationEntry(poId, body),
    onSuccess: () => {
      setMessage('');
      setFollowUpNeeded(false);
      // Invalidate both PO and supplier conversation queries
      queryClient.invalidateQueries({ queryKey: ['po-conversation'] });
      queryClient.invalidateQueries({ queryKey: ['supplier-conversation'] });
      queryClient.invalidateQueries({ queryKey: ['open-follow-ups'] });
      onSuccess();
    },
  });

  const handleSubmit = () => {
    const trimmed = message.trim();
    if (!trimmed) return;
    addMutation.mutate({
      entry_type: entryType,
      message: trimmed,
      follow_up_needed: followUpNeeded,
    });
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    // Ctrl/Cmd + Enter to submit
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <div className="border-t border-gray-200 dark:border-gray-700 p-3 space-y-2 bg-white dark:bg-gray-800/50">
      {/* Entry type selector */}
      <div className="flex items-center gap-1.5 flex-wrap">
        {MANUAL_ENTRY_TYPES.map((type) => {
          const cfg = ENTRY_TYPE_CONFIG[type];
          const Icon = cfg.icon;
          const isActive = entryType === type;
          return (
            <button
              key={type}
              type="button"
              onClick={() => setEntryType(type)}
              className={cn(
                'inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium transition-colors min-h-[32px]',
                isActive
                  ? `${cfg.bgColor} ${cfg.iconColor} ring-1 ring-current/20`
                  : 'bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600',
              )}
            >
              <Icon className="h-3 w-3" />
              <span className="hidden sm:inline">{cfg.label}</span>
            </button>
          );
        })}

        <span className="flex-1" />

        {/* Follow-up toggle */}
        <button
          type="button"
          onClick={() => setFollowUpNeeded(!followUpNeeded)}
          className={cn(
            'inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium transition-colors min-h-[32px]',
            followUpNeeded
              ? 'bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400'
              : 'bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600',
          )}
          title="Mark this entry as needing follow-up"
        >
          <Flag className="h-3 w-3" />
          <span className="hidden sm:inline">Follow-up</span>
        </button>
      </div>

      {/* Message textarea + send button */}
      <div className="flex gap-2">
        <textarea
          ref={textareaRef}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Add a note, log a call, summarize an email…"
          rows={2}
          className="flex-1 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 resize-none min-h-[44px]"
        />
        <button
          type="button"
          onClick={handleSubmit}
          disabled={!message.trim() || addMutation.isPending}
          className="flex-shrink-0 rounded-lg bg-primary text-white px-3 py-2 text-sm font-medium hover:bg-primary/90 disabled:opacity-40 disabled:cursor-not-allowed transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
          title="Send (Ctrl+Enter)"
        >
          {addMutation.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Send className="h-4 w-4" />
          )}
        </button>
      </div>

      {/* Error message */}
      {addMutation.isError && (
        <div className="flex items-center gap-1.5 text-xs text-red-600 dark:text-red-400">
          <AlertCircle className="h-3.5 w-3.5 flex-shrink-0" />
          Failed to add entry. Please try again.
        </div>
      )}

      <p className="text-[10px] text-gray-500 dark:text-gray-400">
        Ctrl+Enter to send
      </p>
    </div>
  );
}


// ── Main Component ──────────────────────────────────────────────

export function ConversationThread({
  poId,
  supplierId,
  canEdit = false,
  maxHeight = '500px',
  className,
}: ConversationThreadProps) {
  const queryClient = useQueryClient();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);

  // ── Determine which query to run ──────────────────────────────
  const isSupplierView = !!supplierId && !poId;

  const {
    data: entries = [],
    isLoading,
    isError,
  } = useQuery({
    queryKey: isSupplierView
      ? ['supplier-conversation', supplierId]
      : ['po-conversation', poId],
    queryFn: () =>
      isSupplierView
        ? getSupplierConversation(supplierId!)
        : getPOConversation(poId!),
    enabled: !!(poId || supplierId),
    staleTime: 15_000,
    refetchInterval: 30_000, // poll every 30s for new entries
  });

  // ── Follow-up toggle mutation ─────────────────────────────────
  const followUpMutation = useMutation({
    mutationFn: ({ entryId, resolved }: { entryId: number; resolved: boolean }) =>
      toggleConversationFollowUp(entryId, { resolved }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['po-conversation'] });
      queryClient.invalidateQueries({ queryKey: ['supplier-conversation'] });
      queryClient.invalidateQueries({ queryKey: ['open-follow-ups'] });
    },
  });

  const handleToggleFollowUp = useCallback(
    (entryId: number, resolved: boolean) => {
      followUpMutation.mutate({ entryId, resolved });
    },
    [followUpMutation],
  );

  // ── Auto-scroll to bottom when new entries arrive ─────────────
  useEffect(() => {
    if (autoScroll && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [entries.length, autoScroll]);

  const handleScroll = () => {
    if (!scrollRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = scrollRef.current;
    // If user scrolled up more than 100px from bottom, disable auto-scroll
    setAutoScroll(scrollHeight - scrollTop - clientHeight < 100);
  };

  // ── Count unresolved follow-ups ───────────────────────────────
  const unresolvedCount = entries.filter(
    (e) => e.follow_up_needed && !e.follow_up_resolved_at,
  ).length;

  if (!poId && !supplierId) return null;

  return (
    <div className={cn('flex flex-col rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden bg-white dark:bg-gray-800', className)}>
      {/* ── Header ───────────────────────────────────────────── */}
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/70">
        <div className="flex items-center gap-2">
          <MessageSquare className="h-4 w-4 text-gray-400 dark:text-gray-500" />
          <h3 className="text-sm font-medium text-gray-700 dark:text-gray-300">
            {isSupplierView ? 'Supplier History' : 'Conversation'}
          </h3>
          <span className="text-xs text-gray-500 dark:text-gray-400">
            ({entries.length})
          </span>
        </div>

        {unresolvedCount > 0 && (
          <span className="inline-flex items-center gap-1 rounded-full bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400 px-2 py-0.5 text-[10px] font-medium">
            <Flag className="h-3 w-3" />
            {unresolvedCount} follow-up{unresolvedCount > 1 ? 's' : ''}
          </span>
        )}
      </div>

      {/* ── Scrollable entries ────────────────────────────────── */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="overflow-y-auto space-y-2 p-3"
        style={{ maxHeight }}
      >
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 animate-spin text-gray-400 dark:text-gray-500" />
          </div>
        ) : isError ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <AlertCircle className="h-6 w-6 text-red-400 mb-2" />
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Failed to load conversation
            </p>
          </div>
        ) : entries.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <MessageSquare className="h-6 w-6 text-gray-300 dark:text-gray-600 mb-2" />
            <p className="text-sm text-gray-500 dark:text-gray-400">
              No conversation yet
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
              Add a note, log a call, or summarize an email below
            </p>
          </div>
        ) : (
          entries.map((entry) => (
            <ConversationEntry
              key={entry.id}
              entry={entry}
              canEdit={canEdit}
              onToggleFollowUp={handleToggleFollowUp}
              isTogglingFollowUp={
                followUpMutation.isPending &&
                followUpMutation.variables?.entryId === entry.id
              }
            />
          ))
        )}

        {/* Scroll-to-bottom indicator when auto-scroll is off */}
        {!autoScroll && entries.length > 3 && (
          <button
            type="button"
            onClick={() => {
              setAutoScroll(true);
              if (scrollRef.current) {
                scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
              }
            }}
            className="sticky bottom-0 mx-auto flex items-center gap-1 rounded-full bg-gray-800/80 dark:bg-gray-200/80 text-white dark:text-gray-900 px-3 py-1.5 text-xs font-medium shadow-lg hover:bg-gray-700 dark:hover:bg-gray-300 transition-colors"
          >
            <ChevronDown className="h-3 w-3" />
            Jump to latest
          </button>
        )}
      </div>

      {/* ── Add entry form (PO-level only, not supplier-level) ── */}
      {canEdit && poId && (
        <AddEntryForm
          poId={poId}
          onSuccess={() => setAutoScroll(true)}
        />
      )}
    </div>
  );
}
