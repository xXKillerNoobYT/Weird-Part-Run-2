/**
 * QuestionsTab — One-time questions for a job.
 * Extracted from JobDetailPage.
 */

import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { HelpCircle } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { Button } from '../../../../components/ui/Button';
import { Badge } from '../../../../components/ui/Badge';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { useAuthStore } from '../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../lib/constants';
import { getOneTimeQuestions, createOneTimeQuestion } from '../../../../api/jobs';

export function QuestionsTab({ jobId }: { jobId: number }) {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_JOBS);
  const queryClient = useQueryClient();

  const { data: questions, isLoading } = useQuery({
    queryKey: ['job-one-time-questions', jobId],
    queryFn: () => getOneTimeQuestions(jobId),
    staleTime: 15_000,
  });

  const [showCreate, setShowCreate] = useState(false);
  const [newQuestion, setNewQuestion] = useState('');

  const createMutation = useMutation({
    mutationFn: () => createOneTimeQuestion(jobId, { question_text: newQuestion }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-one-time-questions', jobId] });
      setNewQuestion('');
      setShowCreate(false);
    },
  });

  if (isLoading) return <PageSpinner label="Loading questions..." />;

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button
            size="sm"
            icon={<HelpCircle className="h-4 w-4" />}
            onClick={() => setShowCreate(!showCreate)}
          >
            Ask Question
          </Button>
        </div>
      )}

      {showCreate && (
        <div className="p-3 bg-surface-secondary rounded-lg border border-border space-y-2">
          <textarea
            value={newQuestion}
            onChange={(e) => setNewQuestion(e.target.value)}
            placeholder="Type your one-time question for this job..."
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm min-h-[80px] resize-none"
          />
          <div className="flex justify-end gap-2">
            <Button variant="secondary" size="sm" onClick={() => setShowCreate(false)}>Cancel</Button>
            <Button
              size="sm"
              isLoading={createMutation.isPending}
              onClick={() => newQuestion.trim() && createMutation.mutate()}
            >
              Send
            </Button>
          </div>
        </div>
      )}

      {!questions || questions.length === 0 ? (
        <EmptyState
          icon={<HelpCircle className="h-12 w-12" />}
          title="No One-Time Questions"
          description="One-time questions appear here when the boss asks specific questions about this job."
        />
      ) : (
        questions.map((q) => (
          <div key={q.id} className="p-3 bg-surface border border-border rounded-lg">
            <div className="flex items-start justify-between gap-2">
              <div>
                <p className="text-sm text-gray-900 dark:text-gray-100">{q.question_text}</p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  Asked by {q.created_by_name}
                  {q.target_user_name ? ` to ${q.target_user_name}` : ' (everyone)'}
                </p>
              </div>
              <Badge variant={q.status === 'answered' ? 'success' : q.status === 'pending' ? 'warning' : 'default'}>
                {q.status}
              </Badge>
            </div>
            {q.answer_text && (
              <div className="mt-2 p-2 bg-green-50 dark:bg-green-900/20 rounded text-sm text-green-700 dark:text-green-300">
                <strong>Answer:</strong> {q.answer_text}
              </div>
            )}
          </div>
        ))
      )}
    </div>
  );
}
