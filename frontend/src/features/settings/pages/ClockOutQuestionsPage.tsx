/**
 * ClockOutQuestionsPage — Admin page for managing global clock-out questions.
 *
 * Bosses use this page (in Settings) to create, edit, reorder, and deactivate
 * the questions that every worker answers when clocking out.
 *
 * Features:
 * - Add new questions (text, yes/no, or photo type)
 * - Drag-to-reorder via up/down arrows (simplified — no library dependency)
 * - Edit existing questions inline
 * - Soft-delete (deactivate) questions
 * - Toggle required/optional
 *
 * Questions are global — they apply to ALL jobs.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  MessageSquare, Plus, GripVertical, ArrowUp, ArrowDown,
  Trash2, Edit2, Check, X, ToggleLeft, ToggleRight,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
  getGlobalQuestions,
  createGlobalQuestion,
  updateGlobalQuestion,
  reorderGlobalQuestions,
  deactivateGlobalQuestion,
} from '../../../api/jobs';
import type { ClockOutQuestionResponse, ClockOutQuestionCreate, QuestionAnswerType } from '../../../lib/types';

const ANSWER_TYPE_LABELS: Record<QuestionAnswerType, string> = {
  text: 'Text',
  yes_no: 'Yes / No',
  photo: 'Photo',
};

export function ClockOutQuestionsPage() {
  const queryClient = useQueryClient();

  // ── State ──────────────────────────────────────────────────────
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [formText, setFormText] = useState('');
  const [formType, setFormType] = useState<QuestionAnswerType>('text');
  const [formRequired, setFormRequired] = useState(true);

  // ── Queries ────────────────────────────────────────────────────
  const { data: questions, isLoading } = useQuery({
    queryKey: ['global-questions'],
    queryFn: () => getGlobalQuestions(false), // Include inactive for admin view
  });

  // ── Mutations ──────────────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: (q: ClockOutQuestionCreate) => createGlobalQuestion(q),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['global-questions'] });
      resetForm();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: ClockOutQuestionCreate }) =>
      updateGlobalQuestion(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['global-questions'] });
      resetForm();
    },
  });

  const reorderMutation = useMutation({
    mutationFn: (ids: number[]) => reorderGlobalQuestions(ids),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['global-questions'] }),
  });

  const deactivateMutation = useMutation({
    mutationFn: (id: number) => deactivateGlobalQuestion(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['global-questions'] }),
  });

  // ── Helpers ────────────────────────────────────────────────────
  function resetForm() {
    setShowForm(false);
    setEditingId(null);
    setFormText('');
    setFormType('text');
    setFormRequired(true);
  }

  function startEdit(q: ClockOutQuestionResponse) {
    setEditingId(q.id);
    setFormText(q.question_text);
    setFormType(q.answer_type);
    setFormRequired(q.is_required);
    setShowForm(true);
  }

  function handleSubmit() {
    const data: ClockOutQuestionCreate = {
      question_text: formText.trim(),
      answer_type: formType,
      is_required: formRequired,
    };
    if (!data.question_text) return;

    if (editingId) {
      updateMutation.mutate({ id: editingId, data });
    } else {
      createMutation.mutate(data);
    }
  }

  function moveQuestion(index: number, direction: 'up' | 'down') {
    if (!questions) return;
    const activeQuestions = questions.filter((q) => q.is_active);
    const newOrder = [...activeQuestions];
    const targetIdx = direction === 'up' ? index - 1 : index + 1;
    if (targetIdx < 0 || targetIdx >= newOrder.length) return;

    [newOrder[index], newOrder[targetIdx]] = [newOrder[targetIdx], newOrder[index]];
    reorderMutation.mutate(newOrder.map((q) => q.id));
  }

  if (isLoading) return <PageSpinner label="Loading questions..." />;

  const activeQuestions = questions?.filter((q) => q.is_active) ?? [];
  const inactiveQuestions = questions?.filter((q) => !q.is_active) ?? [];

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Clock-Out Questions
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Manage the questions workers answer at clock-out. These apply globally to all jobs.
          </p>
        </div>
        {!showForm && (
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => { resetForm(); setShowForm(true); }}
          >
            Add Question
          </Button>
        )}
      </div>

      {/* Add / Edit Form */}
      {showForm && (
        <div className="bg-surface border border-blue-200 dark:border-blue-800 rounded-lg p-4 space-y-3">
          <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {editingId ? 'Edit Question' : 'New Question'}
          </h3>

          {/* Question text */}
          <textarea
            value={formText}
            onChange={(e) => setFormText(e.target.value)}
            placeholder="Enter the question text..."
            rows={2}
            className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          {/* Type + Required row */}
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <label className="text-xs text-gray-500 dark:text-gray-400">Type:</label>
              <select
                value={formType}
                onChange={(e) => setFormType(e.target.value as QuestionAnswerType)}
                className="px-2 py-1.5 text-xs border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
              >
                <option value="text">Text</option>
                <option value="yes_no">Yes / No</option>
                <option value="photo">Photo</option>
              </select>
            </div>
            <button
              onClick={() => setFormRequired(!formRequired)}
              className="flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-300"
            >
              {formRequired ? (
                <ToggleRight className="h-5 w-5 text-blue-500" />
              ) : (
                <ToggleLeft className="h-5 w-5 text-gray-400" />
              )}
              {formRequired ? 'Required' : 'Optional'}
            </button>
          </div>

          {/* Actions */}
          <div className="flex items-center gap-2 pt-1">
            <Button
              size="sm"
              icon={<Check className="h-4 w-4" />}
              onClick={handleSubmit}
              isLoading={createMutation.isPending || updateMutation.isPending}
              disabled={!formText.trim()}
            >
              {editingId ? 'Save Changes' : 'Add Question'}
            </Button>
            <Button size="sm" variant="secondary" icon={<X className="h-4 w-4" />} onClick={resetForm}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {/* Active Questions List */}
      {activeQuestions.length === 0 && !showForm ? (
        <EmptyState
          icon={<MessageSquare className="h-12 w-12" />}
          title="No Questions"
          description="Add clock-out questions that workers must answer when ending their shift."
        />
      ) : (
        <div className="space-y-2">
          {activeQuestions.map((q, idx) => (
            <div
              key={q.id}
              className="flex items-center gap-3 p-4 bg-surface border border-border rounded-lg"
            >
              {/* Order number */}
              <span className="text-sm font-bold text-gray-400 dark:text-gray-500 w-5 text-center shrink-0">
                {idx + 1}
              </span>

              {/* Reorder arrows */}
              <div className="flex flex-col gap-0.5">
                <button
                  onClick={() => moveQuestion(idx, 'up')}
                  disabled={idx === 0 || reorderMutation.isPending}
                  className="p-0.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 disabled:opacity-30 transition-colors"
                >
                  <ArrowUp className="h-3.5 w-3.5" />
                </button>
                <button
                  onClick={() => moveQuestion(idx, 'down')}
                  disabled={idx === activeQuestions.length - 1 || reorderMutation.isPending}
                  className="p-0.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 disabled:opacity-30 transition-colors"
                >
                  <ArrowDown className="h-3.5 w-3.5" />
                </button>
              </div>

              {/* Question content */}
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-gray-900 dark:text-white leading-snug">
                  {q.question_text}
                </p>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-xs px-1.5 py-0.5 rounded font-medium bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400">
                    {ANSWER_TYPE_LABELS[q.answer_type]}
                  </span>
                  <span className={`text-xs font-medium ${q.is_required ? 'text-red-500 dark:text-red-400' : 'text-gray-400 dark:text-gray-500'}`}>
                    {q.is_required ? 'Required' : 'Optional'}
                  </span>
                </div>
              </div>

              {/* Action buttons */}
              <div className="flex items-center gap-1 shrink-0">
                <button
                  onClick={() => startEdit(q)}
                  className="p-1.5 text-gray-400 hover:text-blue-500 dark:text-gray-500 dark:hover:text-blue-400 transition-colors rounded hover:bg-gray-100 dark:hover:bg-gray-700"
                  title="Edit question"
                >
                  <Edit2 className="h-4 w-4" />
                </button>
                <button
                  onClick={() => {
                    if (confirm('Deactivate this question? It will no longer appear during clock-out.')) {
                      deactivateMutation.mutate(q.id);
                    }
                  }}
                  className="p-1.5 text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-400 transition-colors rounded hover:bg-gray-100 dark:hover:bg-gray-700"
                  title="Deactivate question"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Inactive Questions (collapsed) */}
      {inactiveQuestions.length > 0 && (
        <div className="pt-4 border-t border-border">
          <h3 className="text-xs font-medium text-gray-400 dark:text-gray-500 uppercase tracking-wider mb-2">
            Deactivated ({inactiveQuestions.length})
          </h3>
          <div className="space-y-1">
            {inactiveQuestions.map((q) => (
              <div
                key={q.id}
                className="flex items-center gap-2 p-2 bg-gray-50 dark:bg-gray-800/30 border border-border rounded-lg opacity-50"
              >
                <p className="text-sm text-gray-500 dark:text-gray-400 line-through flex-1">
                  {q.question_text}
                </p>
                <span className="text-xs text-gray-400 dark:text-gray-500">
                  {ANSWER_TYPE_LABELS[q.answer_type]}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
