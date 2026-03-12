/**
 * CSVImportModal — reusable CSV file upload modal for bulk import operations.
 *
 * Accepts a generic `importFn` that performs the actual API call.
 * Shows file selection, import progress, and results (created, skipped, errors).
 * Used by: EmployeeListPage, CustomersPage, ContractorsPage.
 */

import { useState, useRef } from 'react';
import { useMutation } from '@tanstack/react-query';
import {
    Upload, CheckCircle2, AlertTriangle, FileText, Info, X,
} from 'lucide-react';
import { Modal } from './Modal';
import { Button } from './Button';
import { Badge } from './Badge';


export interface CSVImportResult {
    created: number;
    skipped: number;
    errors: { row: number; error: string }[];
}

interface CSVImportModalProps {
    isOpen: boolean;
    onClose: () => void;
    /** Title shown in the modal header */
    title: string;
    /** Description of what's being imported */
    description: string;
    /** Expected CSV columns — shown as a hint */
    expectedColumns: string;
    /** The async function that uploads the file and returns import results */
    importFn: (file: File) => Promise<CSVImportResult>;
    /** Called after a successful import to refresh data */
    onSuccess?: () => void;
}


export function CSVImportModal({
    isOpen, onClose, title, description, expectedColumns, importFn, onSuccess,
}: CSVImportModalProps) {
    const fileInputRef = useRef<HTMLInputElement>(null);
    const [selectedFile, setSelectedFile] = useState<File | null>(null);
    const [result, setResult] = useState<CSVImportResult | null>(null);

    const importMutation = useMutation({
        mutationFn: (file: File) => importFn(file),
        onSuccess: (data) => {
            setResult(data);
            setSelectedFile(null);
            if (fileInputRef.current) fileInputRef.current.value = '';
            onSuccess?.();
        },
    });

    const handleClose = () => {
        setSelectedFile(null);
        setResult(null);
        importMutation.reset();
        onClose();
    };

    return (
        <Modal isOpen={isOpen} onClose={handleClose} title={title} size="md">
            <div className="space-y-4">
                {/* Info */}
                <div className="p-3 rounded-lg bg-gray-50 dark:bg-gray-700/30 border border-gray-200 dark:border-gray-600">
                    <div className="flex items-start gap-3">
                        <Info className="h-5 w-5 text-primary-500 mt-0.5 shrink-0" />
                        <div className="text-sm text-gray-600 dark:text-gray-300 space-y-1">
                            <p>{description}</p>
                            <p className="text-xs text-gray-500 dark:text-gray-400">
                                <strong>Expected columns:</strong> {expectedColumns}
                            </p>
                            <p className="text-xs text-gray-500 dark:text-gray-400">
                                Duplicates (by name) are automatically skipped.
                            </p>
                        </div>
                    </div>
                </div>

                {/* File input */}
                <div className="space-y-2">
                    <input
                        ref={fileInputRef}
                        type="file"
                        accept=".csv,text/csv"
                        onChange={(e) => {
                            setSelectedFile(e.target.files?.[0] ?? null);
                            setResult(null);
                        }}
                        className="block w-full text-sm text-gray-500 dark:text-gray-400
              file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0
              file:text-sm file:font-medium
              file:bg-primary-50 file:text-primary-600
              dark:file:bg-primary-900/30 dark:file:text-primary-400
              hover:file:bg-primary-100 dark:hover:file:bg-primary-900/50
              cursor-pointer"
                    />
                    {selectedFile && (
                        <p className="text-sm text-gray-500 dark:text-gray-400">
                            Selected: <strong>{selectedFile.name}</strong> ({(selectedFile.size / 1024).toFixed(1)} KB)
                        </p>
                    )}
                </div>

                {/* Import button */}
                <Button
                    icon={<Upload className="h-4 w-4" />}
                    onClick={() => selectedFile && importMutation.mutate(selectedFile)}
                    isLoading={importMutation.isPending}
                    disabled={!selectedFile}
                    fullWidth
                >
                    Import CSV
                </Button>

                {/* Error */}
                {importMutation.isError && (
                    <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
                        Import failed: {(importMutation.error as any)?.message ?? 'Unknown error'}
                    </div>
                )}

                {/* Results */}
                {result && (
                    <div className="space-y-3 pt-2 border-t border-gray-200 dark:border-gray-700">
                        <div className="flex flex-wrap gap-2">
                            <Badge variant="success">
                                <CheckCircle2 className="h-3.5 w-3.5 mr-1" />
                                {result.created} created
                            </Badge>
                            {result.skipped > 0 && (
                                <Badge variant="default">
                                    <FileText className="h-3.5 w-3.5 mr-1" />
                                    {result.skipped} skipped (duplicates)
                                </Badge>
                            )}
                            {result.errors.length > 0 && (
                                <Badge variant="danger">
                                    <AlertTriangle className="h-3.5 w-3.5 mr-1" />
                                    {result.errors.length} error{result.errors.length !== 1 ? 's' : ''}
                                </Badge>
                            )}
                        </div>

                        {result.created + result.skipped > 0 && result.errors.length === 0 && (
                            <div className="p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg text-sm text-green-600 dark:text-green-400">
                                All rows processed successfully!
                            </div>
                        )}

                        {result.errors.length > 0 && (
                            <div className="max-h-40 overflow-y-auto space-y-1">
                                {result.errors.slice(0, 20).map((err, i) => (
                                    <div
                                        key={i}
                                        className="p-2 bg-red-50 dark:bg-red-900/10 border border-red-100 dark:border-red-900/30 rounded text-xs text-red-600 dark:text-red-400 font-mono"
                                    >
                                        Row {err.row}: {err.error}
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>
                )}
            </div>

            {/* Footer */}
            <div className="flex justify-end mt-4 pt-3 border-t border-gray-200 dark:border-gray-700">
                <Button variant="ghost" size="sm" onClick={handleClose}>
                    <X className="h-4 w-4 mr-1" />
                    Close
                </Button>
            </div>
        </Modal>
    );
}
