/**
 * QAQuestionForm — form for asking a new Q&A question.
 *
 * Fields: subject, body, priority, optional photo attachment.
 * Requires a job_id (selected from a job picker).
 */

import { useState } from 'react';
import {
  MessageSquareWarning,
  Paperclip,
  X,
  Loader2,
} from 'lucide-react';
import type { AskQuestionRequest, QAPriority } from '../../../lib/types';

interface QAQuestionFormProps {
  /** Pre-selected job ID (if opened from a job context) */
  defaultJobId?: number;
  /** Available jobs for the picker */
  jobs?: Array<{ id: number; job_number: string; name: string }>;
  onSubmit: (body: AskQuestionRequest) => void;
  onCancel: () => void;
  isSubmitting?: boolean;
}

const PRIORITY_OPTIONS = [
  { value: 'low', label: 'Low', color: 'text-gray-500' },
  { value: 'normal', label: 'Normal', color: 'text-blue-600 dark:text-blue-400' },
  { value: 'high', label: 'High', color: 'text-amber-600 dark:text-amber-400' },
  { value: 'urgent', label: 'Urgent', color: 'text-red-600 dark:text-red-400' },
];

export function QAQuestionForm({
  defaultJobId,
  jobs = [],
  onSubmit,
  onCancel,
  isSubmitting = false,
}: QAQuestionFormProps) {
  const [jobId, setJobId] = useState<number | ''>(defaultJobId ?? '');
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [priority, setPriority] = useState('normal');
  const [mediaPath, setMediaPath] = useState<string | null>(null);
  const [mediaFile, setMediaFile] = useState<File | null>(null);

  const canSubmit = jobId !== '' && subject.trim().length > 0 && body.trim().length > 0;

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setMediaFile(file);
      // In production, this would upload via API and get a path back.
      // For now, create a local preview URL.
      setMediaPath(URL.createObjectURL(file));
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;

    onSubmit({
      job_id: Number(jobId),
      subject: subject.trim(),
      body: body.trim(),
      priority: priority as QAPriority,
      media_path: mediaPath?.startsWith('blob:') ? undefined : mediaPath ?? undefined,
    });
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="flex items-center gap-2 mb-4">
        <MessageSquareWarning className="h-5 w-5 text-amber-500" />
        <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
          Ask a Question
        </h3>
      </div>

      {/* Job picker (if no default) */}
      {!defaultJobId && (
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Job
          </label>
          <select
            value={jobId}
            onChange={(e) => setJobId(e.target.value ? Number(e.target.value) : '')}
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
          >
            <option value="">Select a job...</option>
            {jobs.map((j) => (
              <option key={j.id} value={j.id}>
                {j.job_number} — {j.name}
              </option>
            ))}
          </select>
        </div>
      )}

      {/* Subject */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          Subject
        </label>
        <input
          type="text"
          value={subject}
          onChange={(e) => setSubject(e.target.value)}
          placeholder="Brief description of the question..."
          maxLength={200}
          className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
        />
      </div>

      {/* Body */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          Details
        </label>
        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder="Describe the issue, what you've tried, and what you need answered..."
          rows={4}
          className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm resize-y focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
        />
      </div>

      {/* Priority */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          Priority
        </label>
        <div className="flex gap-2 flex-wrap">
          {PRIORITY_OPTIONS.map((opt) => (
            <button
              key={opt.value}
              type="button"
              onClick={() => setPriority(opt.value)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors ${
                priority === opt.value
                  ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
                  : 'border-border bg-surface hover:bg-gray-50 dark:hover:bg-gray-700 text-gray-600 dark:text-gray-400'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {/* Photo attachment */}
      <div>
        {mediaFile ? (
          <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
            <Paperclip className="h-4 w-4" />
            <span className="truncate">{mediaFile.name}</span>
            <button
              type="button"
              onClick={() => { setMediaFile(null); setMediaPath(null); }}
              className="p-0.5 hover:bg-gray-200 dark:hover:bg-gray-600 rounded"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ) : (
          <label className="inline-flex items-center gap-1.5 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 cursor-pointer">
            <Paperclip className="h-4 w-4" />
            Attach photo
            <input
              type="file"
              accept="image/*"
              onChange={handleFileChange}
              className="hidden"
            />
          </label>
        )}
      </div>

      {/* Actions */}
      <div className="flex justify-end gap-2 pt-2">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 text-sm rounded-lg border border-border hover:bg-gray-50 dark:hover:bg-gray-700"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={!canSubmit || isSubmitting}
          className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
        >
          {isSubmitting && <Loader2 className="h-4 w-4 animate-spin" />}
          Ask Question
        </button>
      </div>
    </form>
  );
}
