/**
 * SendEmailModal — Compose and send a PO or PO group via email.
 *
 * Features:
 *   - Pre-fills recipient from supplier email or rep email
 *   - Auto-generates subject and body (from clipboard text)
 *   - Optional CC recipients
 *   - PDF attachment toggle
 *   - Shows email config status (if not configured, shows setup info)
 *
 * Used by: POManagementTab, ReviewAndSendPage
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import {
    Mail,
    Paperclip,
    AlertCircle,
    CheckCircle2,
    X,
    Plus,
    Settings,
    Loader2,
    Info,
} from 'lucide-react';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import {
    getEmailConfig,
    sendPOEmail,
    sendGroupEmail,
    getPOClipboardText,
    getPOGroupClipboardText,
} from '../../../api/orders';


// ── Types ───────────────────────────────────────────────────────

interface SendEmailModalProps {
    isOpen: boolean;
    onClose: () => void;
    /** PO email sending mode */
    mode: 'po' | 'group';
    /** PO ID (when mode='po') */
    poId?: number;
    /** PO Group ID (when mode='group') */
    groupId?: number;
    /** Pre-fill display info */
    poNumber?: string;
    supplierName?: string;
    /** Pre-fill supplier emails */
    supplierEmail?: string | null;
    repEmail?: string | null;
    /** Callback after successful send */
    onSuccess?: () => void;
}


export function SendEmailModal({
    isOpen,
    onClose,
    mode,
    poId,
    groupId,
    poNumber,
    supplierName,
    supplierEmail,
    repEmail,
    onSuccess,
}: SendEmailModalProps) {
    // ── Form state ──────────────────────────────────────────────
    const [toEmail, setToEmail] = useState('');
    const [toName, setToName] = useState('');
    const [subject, setSubject] = useState('');
    const [bodyText, setBodyText] = useState('');
    const [ccList, setCcList] = useState<string[]>([]);
    const [ccInput, setCcInput] = useState('');
    const [attachPdf, setAttachPdf] = useState(true);
    const [sent, setSent] = useState(false);

    // ── Email config check ──────────────────────────────────────
    const configQ = useQuery({
        queryKey: ['email-config'],
        queryFn: getEmailConfig,
        enabled: isOpen,
        staleTime: 60_000,
    });

    // ── Pre-fill body from clipboard text ─────────────────────
    const clipboardQ = useQuery({
        queryKey: mode === 'po'
            ? ['po-clipboard-email', poId]
            : ['group-clipboard-email', groupId],
        queryFn: () =>
            mode === 'po' && poId
                ? getPOClipboardText(poId)
                : mode === 'group' && groupId
                    ? getPOGroupClipboardText(groupId)
                    : Promise.resolve({ text: '' }),
        enabled: isOpen && ((mode === 'po' && !!poId) || (mode === 'group' && !!groupId)),
        staleTime: 30_000,
    });

    // ── Initialize form when modal opens ──────────────────────
    useEffect(() => {
        if (isOpen) {
            setToEmail(supplierEmail || repEmail || '');
            setToName(supplierName || '');
            setSubject(
                mode === 'group'
                    ? `Purchase Orders — ${supplierName || 'Order Bundle'}`
                    : `Purchase Order ${poNumber || ''} — ${supplierName || ''}`
            );
            setAttachPdf(true);
            setCcList([]);
            setCcInput('');
            setSent(false);
        }
    }, [isOpen, supplierEmail, repEmail, supplierName, poNumber, mode]);

    // Pre-fill body when clipboard text arrives
    useEffect(() => {
        if (clipboardQ.data?.text && !bodyText) {
            setBodyText(clipboardQ.data.text);
        }
    }, [clipboardQ.data, bodyText]);

    // ── Send mutations ──────────────────────────────────────────
    const sendPOMut = useMutation({
        mutationFn: () =>
            sendPOEmail(poId!, {
                to_email: toEmail.trim(),
                to_name: toName.trim() || undefined,
                subject: subject.trim() || undefined,
                body_text: bodyText.trim() || undefined,
                cc: ccList.length > 0 ? ccList : undefined,
                attach_pdf: attachPdf,
            }),
        onSuccess: () => {
            setSent(true);
            onSuccess?.();
        },
    });

    const sendGroupMut = useMutation({
        mutationFn: () =>
            sendGroupEmail(groupId!, {
                to_email: toEmail.trim(),
                to_name: toName.trim() || undefined,
                subject: subject.trim() || undefined,
                body_text: bodyText.trim() || undefined,
                cc: ccList.length > 0 ? ccList : undefined,
            }),
        onSuccess: () => {
            setSent(true);
            onSuccess?.();
        },
    });

    const isSending = sendPOMut.isPending || sendGroupMut.isPending;
    const sendError = sendPOMut.error || sendGroupMut.error;

    // ── Handlers ────────────────────────────────────────────────
    const handleSend = useCallback(() => {
        if (!toEmail.trim()) return;
        if (mode === 'po' && poId) {
            sendPOMut.mutate();
        } else if (mode === 'group' && groupId) {
            sendGroupMut.mutate();
        }
    }, [mode, poId, groupId, toEmail, sendPOMut, sendGroupMut]);

    const handleAddCC = useCallback(() => {
        const email = ccInput.trim();
        if (email && email.includes('@') && !ccList.includes(email)) {
            setCcList((prev) => [...prev, email]);
            setCcInput('');
        }
    }, [ccInput, ccList]);

    const handleRemoveCC = useCallback((email: string) => {
        setCcList((prev) => prev.filter((e) => e !== email));
    }, []);

    const handleCCKeyDown = useCallback(
        (e: React.KeyboardEvent) => {
            if (e.key === 'Enter' || e.key === ',') {
                e.preventDefault();
                handleAddCC();
            }
        },
        [handleAddCC]
    );

    // Pre-fill rep email as CC if supplier email is primary
    const handleAddRepAsCC = useCallback(() => {
        if (repEmail && !ccList.includes(repEmail) && repEmail !== toEmail) {
            setCcList((prev) => [...prev, repEmail]);
        }
    }, [repEmail, ccList, toEmail]);

    // ── Config not ready ────────────────────────────────────────
    const emailConfig = configQ.data;
    const isConfigured = emailConfig?.enabled && emailConfig?.configured;

    return (
        <Modal isOpen={isOpen} onClose={onClose} title="Send Email" size="lg">
            {/* Success state */}
            {sent ? (
                <div className="py-8 text-center space-y-3">
                    <CheckCircle2 className="mx-auto h-12 w-12 text-green-500" />
                    <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                        Email Sent!
                    </h3>
                    <p className="text-sm text-gray-500 dark:text-gray-400">
                        {mode === 'group' ? 'PO bundle' : `PO ${poNumber}`} sent to{' '}
                        <strong>{toEmail}</strong>
                    </p>
                    <Button variant="primary" onClick={onClose}>
                        Done
                    </Button>
                </div>
            ) : configQ.isLoading ? (
                <div className="py-8 flex items-center justify-center gap-2">
                    <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
                    <span className="text-sm text-gray-500">Checking email configuration…</span>
                </div>
            ) : !isConfigured ? (
                /* Not configured */
                <div className="space-y-4">
                    <div className="flex items-start gap-3 p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg">
                        <Settings className="h-5 w-5 text-amber-500 flex-shrink-0 mt-0.5" />
                        <div>
                            <h3 className="text-sm font-semibold text-amber-800 dark:text-amber-300">
                                Email Not Configured
                            </h3>
                            <p className="text-sm text-amber-700 dark:text-amber-400 mt-1">
                                SMTP settings need to be configured before sending emails.
                                Add the following to your <code className="bg-amber-100 dark:bg-amber-900/40 px-1 rounded">.env</code> file:
                            </p>
                            <pre className="mt-2 text-xs bg-amber-100 dark:bg-amber-900/30 p-3 rounded-lg overflow-x-auto text-amber-800 dark:text-amber-300">
                                {`EMAIL_ENABLED=true
SMTP_HOST=smtp.yourprovider.com
SMTP_PORT=587
SMTP_USER=your@email.com
SMTP_PASSWORD=your-password
EMAIL_FROM=orders@yourcompany.com
EMAIL_FROM_NAME=Your Company`}
                            </pre>
                        </div>
                    </div>

                    <div className="flex justify-end">
                        <Button variant="secondary" onClick={onClose}>
                            Close
                        </Button>
                    </div>
                </div>
            ) : (
                /* Compose form */
                <form
                    onSubmit={(e) => { e.preventDefault(); handleSend(); }}
                    className="space-y-4"
                >
                    {/* Error banner */}
                    {sendError && (
                        <div className="flex items-start gap-2 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
                            <AlertCircle className="h-4 w-4 text-red-500 flex-shrink-0 mt-0.5" />
                            <p className="text-sm text-red-600 dark:text-red-400">
                                {(sendError as Error).message || 'Failed to send email'}
                            </p>
                        </div>
                    )}

                    {/* To */}
                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            To
                        </label>
                        <div className="flex items-center gap-2">
                            <input
                                type="email"
                                required
                                value={toEmail}
                                onChange={(e) => setToEmail(e.target.value)}
                                placeholder="supplier@example.com"
                                className="flex-1 rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                            />
                            {/* Quick-fill buttons */}
                            {supplierEmail && toEmail !== supplierEmail && (
                                <button
                                    type="button"
                                    onClick={() => setToEmail(supplierEmail)}
                                    className="text-xs text-blue-600 hover:text-blue-700 dark:text-blue-400 whitespace-nowrap"
                                >
                                    Use Office
                                </button>
                            )}
                            {repEmail && toEmail !== repEmail && (
                                <button
                                    type="button"
                                    onClick={() => setToEmail(repEmail)}
                                    className="text-xs text-purple-600 hover:text-purple-700 dark:text-purple-400 whitespace-nowrap"
                                >
                                    Use Rep
                                </button>
                            )}
                        </div>
                    </div>

                    {/* To Name */}
                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Recipient Name <span className="text-gray-400">(optional)</span>
                        </label>
                        <input
                            type="text"
                            value={toName}
                            onChange={(e) => setToName(e.target.value)}
                            placeholder={supplierName || 'Contact name'}
                            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        />
                    </div>

                    {/* CC */}
                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            CC <span className="text-gray-400">(optional)</span>
                        </label>
                        {ccList.length > 0 && (
                            <div className="flex flex-wrap gap-1.5 mb-2">
                                {ccList.map((email) => (
                                    <span
                                        key={email}
                                        className="inline-flex items-center gap-1 rounded-full bg-gray-100 dark:bg-gray-700 px-2.5 py-1 text-xs"
                                    >
                                        {email}
                                        <button
                                            type="button"
                                            onClick={() => handleRemoveCC(email)}
                                            className="text-gray-400 hover:text-red-500"
                                        >
                                            <X className="h-3 w-3" />
                                        </button>
                                    </span>
                                ))}
                            </div>
                        )}
                        <div className="flex items-center gap-2">
                            <input
                                type="email"
                                value={ccInput}
                                onChange={(e) => setCcInput(e.target.value)}
                                onKeyDown={handleCCKeyDown}
                                placeholder="Add CC email…"
                                className="flex-1 rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                            />
                            <button
                                type="button"
                                onClick={handleAddCC}
                                disabled={!ccInput.trim()}
                                className="p-2 rounded-lg bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 disabled:opacity-50 transition-colors"
                            >
                                <Plus className="h-4 w-4" />
                            </button>
                            {repEmail && toEmail !== repEmail && !ccList.includes(repEmail) && (
                                <button
                                    type="button"
                                    onClick={handleAddRepAsCC}
                                    className="text-xs text-purple-600 hover:text-purple-700 dark:text-purple-400 whitespace-nowrap"
                                >
                                    + Rep
                                </button>
                            )}
                        </div>
                    </div>

                    {/* Subject */}
                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Subject
                        </label>
                        <input
                            type="text"
                            value={subject}
                            onChange={(e) => setSubject(e.target.value)}
                            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        />
                    </div>

                    {/* Body */}
                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Message
                        </label>
                        {clipboardQ.isLoading ? (
                            <div className="flex items-center gap-2 py-3 px-3 bg-gray-50 dark:bg-gray-800 rounded-lg">
                                <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
                                <span className="text-xs text-gray-400">Loading order details…</span>
                            </div>
                        ) : (
                            <textarea
                                value={bodyText}
                                onChange={(e) => setBodyText(e.target.value)}
                                rows={10}
                                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm font-mono resize-y focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                                placeholder="Order details will be filled automatically…"
                            />
                        )}
                    </div>

                    {/* Options */}
                    {mode === 'po' && (
                        <div className="flex items-center gap-2 text-sm">
                            <label className="flex items-center gap-2 cursor-pointer">
                                <input
                                    type="checkbox"
                                    checked={attachPdf}
                                    onChange={(e) => setAttachPdf(e.target.checked)}
                                    className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                />
                                <Paperclip className="h-4 w-4 text-gray-400" />
                                <span className="text-gray-700 dark:text-gray-300">
                                    Attach PDF
                                </span>
                            </label>
                        </div>
                    )}

                    {mode === 'group' && (
                        <div className="flex items-center gap-2 p-2.5 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
                            <Info className="h-4 w-4 text-blue-500 flex-shrink-0" />
                            <p className="text-xs text-blue-700 dark:text-blue-400">
                                The bundled PDF with all POs in this group will be attached automatically.
                            </p>
                        </div>
                    )}

                    {/* Actions */}
                    <div className="flex items-center justify-end gap-3 pt-2 border-t border-border">
                        <Button variant="secondary" onClick={onClose} disabled={isSending}>
                            Cancel
                        </Button>
                        <Button
                            variant="primary"
                            type="submit"
                            disabled={!toEmail.trim() || isSending}
                            isLoading={isSending}
                        >
                            <Mail className="h-4 w-4 mr-1.5" />
                            Send Email
                        </Button>
                    </div>
                </form>
            )}
        </Modal>
    );
}
