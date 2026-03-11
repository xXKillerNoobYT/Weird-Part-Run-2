/**
 * ReportTemplateBar — manage saved filter presets for reports.
 *
 * Shows a dropdown of saved templates, a "Save as template" button,
 * and handles loading/saving filter state.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getTemplates,
  createTemplate,
  deleteTemplate,
} from '../../../api/reports';


interface Props {
  reportType: string;
  /** Current filter state to save */
  currentConfig: Record<string, unknown>;
  /** Called when a template is loaded */
  onLoadTemplate: (config: Record<string, unknown>) => void;
}

export default function ReportTemplateBar({ reportType, currentConfig, onLoadTemplate }: Props) {
  const qc = useQueryClient();
  const queryKey = ['report-templates', reportType];

  const { data: templates = [] } = useQuery({
    queryKey,
    queryFn: () => getTemplates(reportType),
  });

  const [showSave, setShowSave] = useState(false);
  const [templateName, setTemplateName] = useState('');

  const saveMut = useMutation({
    mutationFn: () => createTemplate({ name: templateName, report_type: reportType, config_json: currentConfig }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey });
      setShowSave(false);
      setTemplateName('');
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => deleteTemplate(id),
    onSuccess: () => qc.invalidateQueries({ queryKey }),
  });

  return (
    <div className="flex flex-wrap items-center gap-2 no-print">
      {/* Template dropdown */}
      {templates.length > 0 && (
        <div className="relative group">
          <select
            onChange={(e) => {
              const tpl = templates.find((t) => t.id === Number(e.target.value));
              if (tpl) onLoadTemplate(tpl.config_json);
              e.target.value = '';
            }}
            defaultValue=""
            className="text-xs border border-gray-300 dark:border-gray-600 rounded px-2 py-1.5
                       bg-white dark:bg-gray-700 text-gray-700 dark:text-gray-300 min-w-32"
          >
            <option value="" disabled>
              📋 Load Template…
            </option>
            {templates.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
          </select>
        </div>
      )}

      {/* Save template */}
      {showSave ? (
        <div className="flex items-center gap-1">
          <input
            type="text"
            value={templateName}
            onChange={(e) => setTemplateName(e.target.value)}
            placeholder="Template name"
            className="text-xs border border-gray-300 dark:border-gray-600 rounded px-2 py-1.5
                       bg-white dark:bg-gray-700 w-40"
            autoFocus
            onKeyDown={(e) => {
              if (e.key === 'Enter' && templateName.trim()) saveMut.mutate();
              if (e.key === 'Escape') setShowSave(false);
            }}
          />
          <button
            onClick={() => saveMut.mutate()}
            disabled={saveMut.isPending || !templateName.trim()}
            className="px-2 py-1.5 text-xs bg-blue-600 text-white rounded hover:bg-blue-700
                       disabled:opacity-50"
          >
            {saveMut.isPending ? '…' : '💾'}
          </button>
          <button
            onClick={() => setShowSave(false)}
            className="px-2 py-1.5 text-xs bg-gray-200 dark:bg-gray-600 rounded hover:bg-gray-300"
          >
            ✕
          </button>
        </div>
      ) : (
        <button
          onClick={() => setShowSave(true)}
          className="px-2 py-1.5 text-xs border border-gray-300 dark:border-gray-600 rounded
                     text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700"
          title="Save current filters as a template"
        >
          💾 <span className="hidden sm:inline">Save Template</span>
        </button>
      )}

      {/* Manage templates (delete) */}
      {templates.length > 0 && (
        <div className="relative group">
          <button
            className="px-2 py-1.5 text-xs text-gray-400 hover:text-red-500"
            title="Manage templates"
          >
            🗑
          </button>
          <div className="hidden group-hover:block absolute top-full right-0 z-50 mt-1
                          bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700
                          rounded-lg shadow-lg min-w-48 py-1">
            {templates.map((t) => (
              <div key={t.id} className="flex items-center justify-between px-3 py-1.5 text-xs
                                         hover:bg-gray-50 dark:hover:bg-gray-700">
                <span className="text-gray-700 dark:text-gray-300">{t.name}</span>
                <button
                  onClick={() => {
                    if (confirm(`Delete template "${t.name}"?`)) deleteMut.mutate(t.id);
                  }}
                  className="text-red-500 hover:text-red-700 ml-2"
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
