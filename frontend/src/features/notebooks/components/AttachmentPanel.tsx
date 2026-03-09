/**
 * AttachmentPanel — self-contained attachment management for notebook entries.
 *
 * Handles its own queries and mutations so parent components don't need
 * to thread callbacks. Just drop `<AttachmentPanel entryId={...} />` into
 * any entry card.
 *
 * Features:
 * - Lists existing attachments with file size & download link
 * - Upload button (opens native file picker)
 * - Delete button per attachment (with confirmation)
 * - Supports any file type (images, PDFs, documents, etc.)
 */

import { useRef, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Paperclip, Trash2, FileText, Image, File, Download } from 'lucide-react';
import {
    listEntryAttachments,
    uploadEntryAttachment,
    deleteEntryAttachment,
} from '../../../api/notebooks';
import type { NotebookAttachment } from '../../../api/notebooks';
import { toast } from '../../../lib/toast';

interface AttachmentPanelProps {
    entryId: number;
    /** Whether the user can upload/delete */
    canEdit?: boolean;
}

/** Friendly file size display */
function formatFileSize(bytes: number | null): string {
    if (!bytes) return '';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Pick an icon based on file type */
function FileIcon({ fileType }: { fileType: string | null }) {
    if (fileType?.startsWith('image/')) return <Image className="h-3.5 w-3.5 text-blue-400" />;
    if (fileType === 'application/pdf') return <FileText className="h-3.5 w-3.5 text-red-400" />;
    return <File className="h-3.5 w-3.5 text-gray-400" />;
}

export function AttachmentPanel({ entryId, canEdit }: AttachmentPanelProps) {
    const queryClient = useQueryClient();
    const fileInputRef = useRef<HTMLInputElement>(null);
    const [deletingId, setDeletingId] = useState<number | null>(null);

    // ── Query ─────────────────────────────────────────────────────
    const { data: attachments = [] } = useQuery({
        queryKey: ['entry-attachments', entryId],
        queryFn: () => listEntryAttachments(entryId),
    });

    // ── Mutations ─────────────────────────────────────────────────
    const invalidate = () => {
        queryClient.invalidateQueries({ queryKey: ['entry-attachments', entryId] });
    };

    const uploadMut = useMutation({
        mutationFn: (file: File) => uploadEntryAttachment(entryId, file),
        onSuccess: () => {
            invalidate();
            toast.success('Attachment uploaded');
        },
        onError: () => toast.error('Failed to upload attachment'),
    });

    const deleteMut = useMutation({
        mutationFn: (attachmentId: number) => deleteEntryAttachment(attachmentId),
        onSuccess: () => {
            invalidate();
            setDeletingId(null);
            toast.success('Attachment deleted');
        },
        onError: () => {
            setDeletingId(null);
            toast.error('Failed to delete attachment');
        },
    });

    const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (file) {
            uploadMut.mutate(file);
        }
        // Reset input so the same file can be re-selected
        if (fileInputRef.current) fileInputRef.current.value = '';
    };

    const handleDelete = (attachment: NotebookAttachment) => {
        if (window.confirm(`Delete "${attachment.file_name}"?`)) {
            setDeletingId(attachment.id);
            deleteMut.mutate(attachment.id);
        }
    };

    // Don't render anything if no attachments and user can't edit
    if (attachments.length === 0 && !canEdit) return null;

    return (
        <div className="mt-2 pt-2 border-t border-border/50">
            {/* Attachment list */}
            {attachments.length > 0 && (
                <div className="space-y-1 mb-1.5">
                    {attachments.map((att) => (
                        <div
                            key={att.id}
                            className="flex items-center gap-2 px-2 py-1 rounded-md bg-gray-50 dark:bg-gray-800/50 group"
                        >
                            <FileIcon fileType={att.file_type} />
                            <span className="flex-1 min-w-0 text-xs text-gray-700 dark:text-gray-300 truncate">
                                {att.file_name}
                            </span>
                            {att.file_size && (
                                <span className="text-[10px] text-gray-400 dark:text-gray-500 shrink-0">
                                    {formatFileSize(att.file_size)}
                                </span>
                            )}
                            {/* Download link */}
                            <a
                                href={`/api${att.file_path}`}
                                download={att.file_name}
                                className="p-1 rounded text-gray-400 hover:text-blue-500 transition-colors opacity-0 group-hover:opacity-100"
                                title="Download"
                            >
                                <Download className="h-3 w-3" />
                            </a>
                            {/* Delete button */}
                            {canEdit && (
                                <button
                                    onClick={() => handleDelete(att)}
                                    disabled={deletingId === att.id}
                                    className="p-1 rounded text-gray-400 hover:text-red-500 transition-colors opacity-0 group-hover:opacity-100 disabled:opacity-50"
                                    title="Delete attachment"
                                >
                                    <Trash2 className="h-3 w-3" />
                                </button>
                            )}
                        </div>
                    ))}
                </div>
            )}

            {/* Upload button */}
            {canEdit && (
                <>
                    <input
                        ref={fileInputRef}
                        type="file"
                        onChange={handleFileSelect}
                        className="hidden"
                    />
                    <button
                        onClick={() => fileInputRef.current?.click()}
                        disabled={uploadMut.isPending}
                        className="flex items-center gap-1.5 px-2 py-1 text-[11px] font-medium text-gray-500 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-md transition-colors disabled:opacity-50"
                    >
                        {uploadMut.isPending ? (
                            <div className="h-3 w-3 animate-spin rounded-full border-2 border-current border-t-transparent" />
                        ) : (
                            <Paperclip className="h-3 w-3" />
                        )}
                        {attachments.length > 0 ? 'Add file' : 'Attach file'}
                    </button>
                </>
            )}
        </div>
    );
}
