/**
 * RFIListPage — office-only page for managing RFIs sent to GCs.
 *
 * Features:
 * - Filter by job and status
 * - RFI cards with detail expansion
 * - "Send to GC" via native SMS/email compose (sms:/mailto: URLs on mobile,
 *   copy-paste modal on desktop)
 * - Status updates (mark as responded, etc.)
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  FileText,
  Filter,
  Send,
  Mail,
  MessageSquare,
  Phone,
  CheckCircle2,
  Clock,
  XCircle,
  ChevronDown,
  ChevronUp,
  Loader2,
  Copy,
  Check,
} from 'lucide-react';
import { getRFIs, updateRFI } from '../../../api/chat';
import type { RFIResponse, RFIStatus } from '../../../lib/types';

const STATUS_CONFIG: Record<string, { label: string; icon: typeof Clock; className: string }> = {
  draft:     { label: 'Draft',     icon: Clock,        className: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400' },
  sent:      { label: 'Sent',      icon: Send,         className: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' },
  responded: { label: 'Responded', icon: CheckCircle2, className: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300' },
  closed:    { label: 'Closed',    icon: XCircle,      className: 'bg-gray-100 text-gray-500 dark:bg-gray-700 dark:text-gray-500' },
};

export default function RFIListPage() {
  const queryClient = useQueryClient();
  const [filterStatus, setFilterStatus] = useState<RFIStatus | ''>('');
  const [showFilters, setShowFilters] = useState(false);
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [copiedId, setCopiedId] = useState<number | null>(null);

  // ── Data fetching ────────────────────────────────────────────────
  const { data: rfis = [], isLoading } = useQuery({
    queryKey: ['rfis', filterStatus],
    queryFn: () =>
      getRFIs({
        status: filterStatus || undefined,
        limit: 100,
      }),
    refetchInterval: 60_000,
  });

  // ── Update mutation ──────────────────────────────────────────────
  const updateMutation = useMutation({
    mutationFn: ({ id, status, response_text }: { id: number; status?: RFIStatus; response_text?: string }) =>
      updateRFI(id, { status, response_text }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rfis'] });
    },
  });

  // ── Send via native compose ──────────────────────────────────────
  const handleSendSMS = (rfi: RFIResponse) => {
    const phone = rfi.gc_phone;
    if (!phone) return;
    const body = encodeURIComponent(`RFI: ${rfi.subject}\n\n${rfi.body}`);
    window.open(`sms:${phone}?body=${body}`, '_self');
    updateMutation.mutate({ id: rfi.id, status: 'sent_text' });
  };

  const handleSendEmail = (rfi: RFIResponse) => {
    const email = rfi.gc_email;
    if (!email) return;
    const subject = encodeURIComponent(`RFI: ${rfi.subject}`);
    const body = encodeURIComponent(rfi.body);
    window.open(`mailto:${email}?subject=${subject}&body=${body}`, '_self');
    updateMutation.mutate({ id: rfi.id, status: 'sent_email' });
  };

  const handleCopyToClipboard = async (rfi: RFIResponse) => {
    const text = `RFI: ${rfi.subject}\n\n${rfi.body}`;
    try {
      await navigator.clipboard.writeText(text);
      setCopiedId(rfi.id);
      setTimeout(() => setCopiedId(null), 2000);
    } catch {
      // Fallback for older browsers
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      setCopiedId(rfi.id);
      setTimeout(() => setCopiedId(null), 2000);
    }
  };

  // ── Render ───────────────────────────────────────────────────────
  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3 px-4 py-3 border-b border-border bg-surface">
        <div className="flex items-center gap-2">
          <FileText className="h-5 w-5 text-purple-500" />
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            RFIs
          </h2>
          <span className="text-xs text-gray-400">
            {rfis.length} total
          </span>
        </div>
        <button
          onClick={() => setShowFilters(!showFilters)}
          className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 border border-border"
          title="Filter"
        >
          <Filter className="h-4 w-4 text-gray-500" />
        </button>
      </div>

      {/* Filter bar */}
      {showFilters && (
        <div className="flex items-center gap-3 px-4 py-2 border-b border-border bg-surface-secondary">
          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value as RFIStatus | '')}
            className="rounded-lg border border-border bg-surface px-2 py-1 text-sm"
          >
            <option value="">All Statuses</option>
            <option value="draft">Draft</option>
            <option value="sent">Sent</option>
            <option value="responded">Responded</option>
            <option value="closed">Closed</option>
          </select>
        </div>
      )}

      {/* RFI list */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
          </div>
        ) : rfis.length === 0 ? (
          <div className="text-center py-12 px-4">
            <FileText className="h-8 w-8 text-gray-300 mx-auto mb-2" />
            <p className="text-sm text-gray-500 dark:text-gray-400">No RFIs found</p>
            <p className="text-xs text-gray-400 mt-1">
              RFIs are created when Q&A questions are sent to a General Contractor.
            </p>
          </div>
        ) : (
          <div className="divide-y divide-border">
            {rfis.map((rfi) => (
              <RFICard
                key={rfi.id}
                rfi={rfi}
                isExpanded={expandedId === rfi.id}
                onToggle={() => setExpandedId(expandedId === rfi.id ? null : rfi.id)}
                onSendSMS={() => handleSendSMS(rfi)}
                onSendEmail={() => handleSendEmail(rfi)}
                onCopy={() => handleCopyToClipboard(rfi)}
                isCopied={copiedId === rfi.id}
                onMarkResponded={(responseText) =>
                  updateMutation.mutate({ id: rfi.id, status: 'responded', response_text: responseText })
                }
                onClose={() => updateMutation.mutate({ id: rfi.id, status: 'closed' })}
                isUpdating={updateMutation.isPending}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}


// ── RFI Card ────────────────────────────────────────────────────────

function RFICard({
  rfi,
  isExpanded,
  onToggle,
  onSendSMS,
  onSendEmail,
  onCopy,
  isCopied,
  onMarkResponded,
  onClose,
  isUpdating,
}: {
  rfi: RFIResponse;
  isExpanded: boolean;
  onToggle: () => void;
  onSendSMS: () => void;
  onSendEmail: () => void;
  onCopy: () => void;
  isCopied: boolean;
  onMarkResponded: (text: string) => void;
  onClose: () => void;
  isUpdating: boolean;
}) {
  const [responseText, setResponseText] = useState('');
  const statusConf = STATUS_CONFIG[rfi.status] ?? STATUS_CONFIG.draft;
  const StatusIcon = statusConf.icon;

  return (
    <div className="px-4 py-3">
      {/* Summary row */}
      <button
        onClick={onToggle}
        className="w-full text-left flex items-start justify-between gap-3"
      >
        <div className="min-w-0 flex-1">
          <h4 className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {rfi.subject}
          </h4>
          <div className="flex items-center gap-2 mt-0.5 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
            {rfi.job_number && <span>{rfi.job_number}</span>}
            {rfi.gc_name && <span>GC: {rfi.gc_name}</span>}
            {rfi.created_at && (
              <span>{new Date(rfi.created_at).toLocaleDateString()}</span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${statusConf.className}`}>
            <StatusIcon className="h-3 w-3" />
            {statusConf.label}
          </span>
          {isExpanded ? (
            <ChevronUp className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          )}
        </div>
      </button>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="mt-3 space-y-3 pl-0 sm:pl-4">
          {/* Body */}
          <div className="bg-surface-secondary rounded-lg px-3 py-2">
            <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">
              {rfi.body}
            </p>
          </div>

          {/* GC Contact info */}
          {(rfi.gc_phone || rfi.gc_email) && (
            <div className="flex items-center gap-3 text-xs text-gray-500 flex-wrap">
              {rfi.gc_phone && (
                <span className="flex items-center gap-1">
                  <Phone className="h-3 w-3" /> {rfi.gc_phone}
                </span>
              )}
              {rfi.gc_email && (
                <span className="flex items-center gap-1">
                  <Mail className="h-3 w-3" /> {rfi.gc_email}
                </span>
              )}
            </div>
          )}

          {/* Response (if responded) */}
          {rfi.response_text && (
            <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg px-3 py-2">
              <p className="text-xs font-medium text-green-700 dark:text-green-400 mb-1">
                GC Response:
              </p>
              <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">
                {rfi.response_text}
              </p>
              {rfi.responded_at && (
                <p className="text-[10px] text-gray-400 mt-1">
                  {new Date(rfi.responded_at).toLocaleString()}
                </p>
              )}
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center gap-2 flex-wrap">
            {/* Send actions (only if not yet sent/responded) */}
            {['draft'].includes(rfi.status) && (
              <>
                {rfi.gc_phone && (
                  <button
                    onClick={onSendSMS}
                    className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 text-white text-xs rounded-lg hover:bg-blue-700"
                  >
                    <MessageSquare className="h-3.5 w-3.5" />
                    Send SMS
                  </button>
                )}
                {rfi.gc_email && (
                  <button
                    onClick={onSendEmail}
                    className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 text-white text-xs rounded-lg hover:bg-blue-700"
                  >
                    <Mail className="h-3.5 w-3.5" />
                    Send Email
                  </button>
                )}
                <button
                  onClick={onCopy}
                  className="flex items-center gap-1.5 px-3 py-1.5 border border-border text-xs rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700"
                >
                  {isCopied ? (
                    <Check className="h-3.5 w-3.5 text-green-500" />
                  ) : (
                    <Copy className="h-3.5 w-3.5 text-gray-500" />
                  )}
                  {isCopied ? 'Copied!' : 'Copy'}
                </button>
              </>
            )}

            {/* Mark responded */}
            {(['sent_text', 'sent_email', 'sent_app'] as RFIStatus[]).includes(rfi.status) && (
              <div className="flex items-center gap-2 w-full sm:w-auto">
                <input
                  type="text"
                  value={responseText}
                  onChange={(e) => setResponseText(e.target.value)}
                  placeholder="GC response..."
                  className="rounded-lg border border-border bg-surface px-2 py-1.5 text-xs flex-1 sm:w-48"
                />
                <button
                  onClick={() => onMarkResponded(responseText)}
                  disabled={!responseText.trim() || isUpdating}
                  className="flex items-center gap-1 px-3 py-1.5 bg-green-600 text-white text-xs rounded-lg hover:bg-green-700 disabled:opacity-50"
                >
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  Responded
                </button>
              </div>
            )}

            {/* Close */}
            {rfi.status !== 'closed' && (
              <button
                onClick={onClose}
                disabled={isUpdating}
                className="flex items-center gap-1 px-3 py-1.5 border border-border text-xs rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-50"
              >
                <XCircle className="h-3.5 w-3.5 text-gray-500" />
                Close
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
