/**
 * ImportExportPage — bulk import/export parts data via CSV.
 *
 * Features:
 *  - Export: Download full parts catalog as CSV (pricing included if permitted)
 *  - Import: Upload CSV to create/update parts (upsert by part code)
 *  - Import results panel: shows created, updated, and error counts
 *  - Template download: sample CSV with correct headers
 */

import { useState, useRef } from 'react';
import { useMutation } from '@tanstack/react-query';
import {
  FileSpreadsheet, Download, Upload, CheckCircle2,
  AlertTriangle, FileText, Info,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { exportPartsCsv, importPartsCsv } from '../../../api/parts';
import type { ImportResult } from '../../../lib/types';


/** Template CSV content with the columns the import endpoint expects. */
const CSV_TEMPLATE = `category_id,name,description,part_type,code,brand_name,manufacturer_part_number,unit_of_measure,company_cost_price,company_markup_percent,min_stock_level,max_stock_level,target_stock_level,notes
9,"12/2 Romex 250ft","Non-metallic sheathed cable",general,WR-12-2-250,,,ft,89.99,35.0,5,20,10,
6,"Square D 20A Breaker","Single-pole circuit breaker",specific,BR-SQD-20A,Square D,QO120,each,12.50,40.0,10,50,25,`;


export function ImportExportPage() {
  const { hasPermission } = useAuthStore();
  const canSeePricing = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // ── Import state ──────────────────────────────────
  const [importResult, setImportResult] = useState<ImportResult | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);

  // ── Export mutation ────────────────────────────────
  const exportMutation = useMutation({
    mutationFn: exportPartsCsv,
    onSuccess: (blob) => {
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `parts-export-${new Date().toISOString().slice(0, 10)}.csv`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    },
  });

  // ── Import mutation ───────────────────────────────
  const importMutation = useMutation({
    mutationFn: importPartsCsv,
    onSuccess: (result) => {
      setImportResult(result);
      setSelectedFile(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
    },
  });

  // ── Template download helper ──────────────────────
  const downloadTemplate = () => {
    const blob = new Blob([CSV_TEMPLATE], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'parts-import-template.csv';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  // ── File selection handler ────────────────────────
  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0] ?? null;
    setSelectedFile(file);
    setImportResult(null);
  };

  const handleImport = () => {
    if (selectedFile) {
      importMutation.mutate(selectedFile);
    }
  };

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* ═══════════════════════════════════════════
            EXPORT CARD
            ═══════════════════════════════════════════ */}
        <Card>
          <CardHeader
            title="Export Parts"
            subtitle="Download your parts catalog as a CSV file."
          />

          <div className="space-y-4">
            <div className="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/30 border border-gray-200 dark:border-gray-600">
              <div className="flex items-start gap-3">
                <FileSpreadsheet className="h-8 w-8 text-primary-500 mt-0.5 shrink-0" />
                <div className="text-sm text-gray-600 dark:text-gray-300 space-y-1">
                  <p>Exports all parts including hierarchy (category, style, type, color), code, name, brand, unit of measure, stock levels, and notes.</p>
                  {canSeePricing ? (
                    <p className="text-green-600 dark:text-green-400">
                      <CheckCircle2 className="inline h-3.5 w-3.5 mr-1" />
                      Pricing columns (cost, markup, sell) will be included.
                    </p>
                  ) : (
                    <p className="text-amber-600 dark:text-amber-400">
                      <Info className="inline h-3.5 w-3.5 mr-1" />
                      Pricing columns are hidden based on your permissions.
                    </p>
                  )}
                </div>
              </div>
            </div>

            <Button
              icon={<Download className="h-4 w-4" />}
              onClick={() => exportMutation.mutate()}
              isLoading={exportMutation.isPending}
              fullWidth
            >
              Export Catalog CSV
            </Button>

            {exportMutation.isError && (
              <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
                Export failed: {(exportMutation.error as any)?.message ?? 'Unknown error'}
              </div>
            )}
          </div>
        </Card>

        {/* ═══════════════════════════════════════════
            IMPORT CARD
            ═══════════════════════════════════════════ */}
        <Card>
          <CardHeader
            title="Import Parts"
            subtitle="Upload a CSV file to create or update parts."
          />

          <div className="space-y-4">
            {/* Info panel */}
            <div className="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/30 border border-gray-200 dark:border-gray-600">
              <div className="flex items-start gap-3">
                <Upload className="h-8 w-8 text-primary-500 mt-0.5 shrink-0" />
                <div className="text-sm text-gray-600 dark:text-gray-300 space-y-1">
                  <p>Upload a CSV with part data. Each row requires a <strong>category_id</strong> and <strong>name</strong>:</p>
                  <ul className="list-disc list-inside ml-1 text-gray-500 dark:text-gray-400">
                    <li>Matching parts by hierarchy + name are <strong>updated</strong></li>
                    <li>Non-matching rows are <strong>created</strong></li>
                    <li>Code is optional for general parts</li>
                  </ul>
                </div>
              </div>
            </div>

            {/* Template download */}
            <button
              onClick={downloadTemplate}
              className="flex items-center gap-2 text-sm text-primary-500 hover:text-primary-600 hover:underline"
            >
              <FileText className="h-4 w-4" />
              Download CSV template with example data
            </button>

            {/* File input */}
            <div className="space-y-2">
              <input
                ref={fileInputRef}
                type="file"
                accept=".csv,text/csv"
                onChange={handleFileSelect}
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

            <Button
              icon={<Upload className="h-4 w-4" />}
              onClick={handleImport}
              isLoading={importMutation.isPending}
              disabled={!selectedFile}
              fullWidth
            >
              Import CSV
            </Button>

            {importMutation.isError && (
              <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
                Import failed: {(importMutation.error as any)?.message ?? 'Unknown error'}
              </div>
            )}
          </div>
        </Card>
      </div>

      {/* ═══════════════════════════════════════════
          IMPORT RESULTS
          ═══════════════════════════════════════════ */}
      {importResult && (
        <Card>
          <CardHeader
            title="Import Results"
            subtitle={`Processed on ${new Date().toLocaleString()}`}
          />

          {/* Summary badges */}
          <div className="flex flex-wrap gap-3 mb-4">
            <Badge variant="success">
              <CheckCircle2 className="h-3.5 w-3.5 mr-1" />
              {importResult.created} created
            </Badge>
            <Badge variant="primary">
              <FileSpreadsheet className="h-3.5 w-3.5 mr-1" />
              {importResult.updated} updated
            </Badge>
            {importResult.total_errors > 0 && (
              <Badge variant="danger">
                <AlertTriangle className="h-3.5 w-3.5 mr-1" />
                {importResult.total_errors} error{importResult.total_errors !== 1 ? 's' : ''}
              </Badge>
            )}
          </div>

          {/* Success summary */}
          {importResult.created + importResult.updated > 0 && importResult.total_errors === 0 && (
            <div className="p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg text-sm text-green-600 dark:text-green-400 mb-4">
              All rows imported successfully!
            </div>
          )}

          {/* Error details */}
          {importResult.errors.length > 0 && (
            <div className="space-y-2">
              <h4 className="text-sm font-medium text-red-600 dark:text-red-400">Errors:</h4>
              <div className="max-h-60 overflow-y-auto space-y-1.5">
                {importResult.errors.map((err, i) => (
                  <div
                    key={i}
                    className="p-2 bg-red-50 dark:bg-red-900/10 border border-red-100 dark:border-red-900/30 rounded text-sm text-red-600 dark:text-red-400 font-mono"
                  >
                    {err}
                  </div>
                ))}
              </div>
            </div>
          )}
        </Card>
      )}
    </div>
  );
}
