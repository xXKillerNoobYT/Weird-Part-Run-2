/**
 * ShareReportModal — generate and manage shareable links for reports.
 *
 * Shows a modal with:
 * - Generate new share link with optional expiry
 * - Copy link to clipboard
 * - List/revoke existing share tokens
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { X } from 'lucide-react';
import {
  createShareToken,
  getShareTokens,
  revokeShareToken,
} from '../../../api/reports';


interface Props {
  isOpen: boolean;
  onClose: () => void;
  reportType: string;
  contextParams: Record<string, unknown>;
  defaultLabel?: string;
}

export default function ShareReportModal({
  isOpen,
  onClose,
  reportType,
  contextParams,
  defaultLabel,
}: Props) {
  const qc = useQueryClient();
  const queryKey = ['report-share-tokens'];

  const { data: tokens = [] } = useQuery({
    queryKey,
    queryFn: getShareTokens,
    enabled: isOpen,
  });

  const [label, setLabel] = useState(defaultLabel || '');
  const [expiryDays, setExpiryDays] = useState<number | undefined>(30);
  const [copied, setCopied] = useState<string | null>(null);

  const createMut = useMutation({
    mutationFn: () =>
      createShareToken({
        report_type: reportType,
        context_params: contextParams,
        label: label || undefined,
        expires_in_days: expiryDays,
      }),
    onSuccess: (token) => {
      qc.invalidateQueries({ queryKey });
      copyToClipboard(token.share_url);
    },
  });

  const revokeMut = useMutation({
    mutationFn: (id: number) => revokeShareToken(id),
    onSuccess: () => qc.invalidateQueries({ queryKey }),
  });

  const copyToClipboard = (url: string) => {
    const fullUrl = `${window.location.origin}${url}`;
    navigator.clipboard.writeText(fullUrl).then(() => {
      setCopied(url);
      setTimeout(() => setCopied(null), 2000);
    });
  };

  // Filter tokens for this report type
  const relevantTokens = tokens.filter((t) => t.report_type === reportType);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
      <div
        className="bg-white dark:bg-gray-800 rounded-xl shadow-2xl w-full max-w-lg mx-4 max-h-[80vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Share Report</h2>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="px-6 py-4 space-y-4">
          {/* Generate new link */}
          <div className="space-y-3">
            <h3 className="text-sm font-medium text-gray-700 dark:text-gray-300">
              Generate Share Link
            </h3>
            <div>
              <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                Label (optional)
              </label>
              <input
                type="text"
                value={label}
                onChange={(e) => setLabel(e.target.value)}
                placeholder="e.g. 'Pre-billing for Job #42 — May 2025'"
                className="w-full text-sm border border-gray-300 dark:border-gray-600 rounded px-3 py-2
                           bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
              />
            </div>
            <div>
              <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                Link expires after
              </label>
              <select
                value={expiryDays ?? ''}
                onChange={(e) => setExpiryDays(e.target.value ? Number(e.target.value) : undefined)}
                className="text-sm border border-gray-300 dark:border-gray-600 rounded px-3 py-2
                           bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
              >
                <option value="7">7 days</option>
                <option value="30">30 days</option>
                <option value="90">90 days</option>
                <option value="365">1 year</option>
                <option value="">Never</option>
              </select>
            </div>
            <button
              onClick={() => createMut.mutate()}
              disabled={createMut.isPending}
              className="w-full py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700
                         disabled:opacity-50 font-medium"
            >
              {createMut.isPending ? 'Generating…' : '🔗 Generate & Copy Link'}
            </button>
            {createMut.isSuccess && (
              <p className="text-xs text-green-600 dark:text-green-400 text-center">
                ✓ Link generated and copied to clipboard!
              </p>
            )}
          </div>

          {/* Existing tokens */}
          {relevantTokens.length > 0 && (
            <div className="pt-2 border-t border-gray-200 dark:border-gray-700">
              <h3 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Active Links ({relevantTokens.length})
              </h3>
              <div className="space-y-2 max-h-48 overflow-y-auto">
                {relevantTokens.map((t) => (
                  <div
                    key={t.id}
                    className="flex items-center justify-between bg-gray-50 dark:bg-gray-700/50
                               rounded-lg px-3 py-2"
                  >
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-gray-800 dark:text-gray-200 truncate">
                        {t.label || 'Unlabeled link'}
                      </p>
                      <p className="text-xs text-gray-500">
                        Created {new Date(t.created_at).toLocaleDateString()}
                        {t.expires_at && ` · Expires ${new Date(t.expires_at).toLocaleDateString()}`}
                        {t.last_accessed_at && ` · Last viewed ${new Date(t.last_accessed_at).toLocaleDateString()}`}
                      </p>
                    </div>
                    <div className="flex items-center gap-1 ml-2">
                      <button
                        onClick={() => copyToClipboard(t.share_url)}
                        className="p-1.5 text-xs rounded hover:bg-gray-200 dark:hover:bg-gray-600"
                        title="Copy link"
                      >
                        {copied === t.share_url ? '✓' : '📋'}
                      </button>
                      <button
                        onClick={() => {
                          if (confirm('Revoke this share link? Anyone using it will lose access.')) {
                            revokeMut.mutate(t.id);
                          }
                        }}
                        className="p-1.5 text-xs text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded"
                        title="Revoke link"
                      >
                        🗑
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
