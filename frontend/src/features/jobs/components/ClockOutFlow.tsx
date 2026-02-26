/**
 * ClockOutFlow — Multi-step clock-out wizard.
 *
 * Displayed when a worker clicks "Clock Out" on a job. Steps:
 *
 * 1. **Questions**: All global clock-out questions + any pending one-time
 *    questions for this user/job. Text inputs, yes/no toggles, and photo
 *    questions are rendered as cards.
 *
 * 2. **Review & Confirm**: Summary of answers, GPS capture, optional notes,
 *    drive time input. Worker confirms and submits.
 *
 * The flow fetches the "clock-out bundle" which combines global + one-time
 * questions into a single payload to minimize round-trips.
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  CheckCircle2, XCircle, MessageSquare, ArrowRight,
  ArrowLeft, Clock, MapPin, Loader2,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { PageSpinner } from '../../../components/ui/Spinner';
import { getClockOutBundle } from '../../../api/jobs';
import { useClockStore } from '../../../stores/clock-store';
import type {
  ClockOutResponseInput,
  OneTimeAnswerInput,
  ClockOutQuestionResponse,
  OneTimeQuestionResponse,
} from '../../../lib/types';

interface ClockOutFlowProps {
  jobId: number;
  laborEntryId: number;
  onComplete: () => void;
  onCancel: () => void;
}

// ── Step 1: Questions ───────────────────────────────────────────

function QuestionStep({
  globalQuestions,
  oneTimeQuestions,
  globalAnswers,
  oneTimeAnswerTexts,
  onGlobalChange,
  onOneTimeChange,
  onNext,
  onCancel,
}: {
  globalQuestions: ClockOutQuestionResponse[];
  oneTimeQuestions: OneTimeQuestionResponse[];
  globalAnswers: Map<number, { text?: string; bool?: boolean }>;
  oneTimeAnswerTexts: Map<number, string>;
  onGlobalChange: (qId: number, value: { text?: string; bool?: boolean }) => void;
  onOneTimeChange: (qId: number, text: string) => void;
  onNext: () => void;
  onCancel: () => void;
}) {
  // Check if all required global questions are answered
  const allRequiredAnswered = globalQuestions
    .filter((q) => q.is_required)
    .every((q) => {
      const answer = globalAnswers.get(q.id);
      if (!answer) return false;
      if (q.answer_type === 'yes_no') return answer.bool !== undefined;
      return !!answer.text?.trim();
    });

  return (
    <div className="space-y-4">
      <div className="text-center mb-2">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          Clock-Out Questions
        </h3>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Answer these before clocking out
        </p>
      </div>

      {/* Global Questions */}
      {globalQuestions.map((q) => {
        const answer = globalAnswers.get(q.id);
        return (
          <div
            key={q.id}
            className="p-3 bg-surface border border-border rounded-lg space-y-2"
          >
            <div className="flex items-start gap-2">
              <MessageSquare className="h-4 w-4 text-gray-400 dark:text-gray-500 mt-0.5 shrink-0" />
              <div className="flex-1">
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  {q.question_text}
                  {q.is_required && <span className="text-red-500 ml-1">*</span>}
                </p>
              </div>
            </div>

            {/* Answer input based on type */}
            {q.answer_type === 'yes_no' ? (
              <div className="flex gap-2 pl-6">
                <button
                  onClick={() => onGlobalChange(q.id, { bool: true })}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                    answer?.bool === true
                      ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300 border border-green-300 dark:border-green-700'
                      : 'bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400 border border-transparent hover:border-gray-300 dark:hover:border-gray-600'
                  }`}
                >
                  <CheckCircle2 className="h-4 w-4" />
                  Yes
                </button>
                <button
                  onClick={() => onGlobalChange(q.id, { bool: false })}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                    answer?.bool === false
                      ? 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300 border border-red-300 dark:border-red-700'
                      : 'bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400 border border-transparent hover:border-gray-300 dark:hover:border-gray-600'
                  }`}
                >
                  <XCircle className="h-4 w-4" />
                  No
                </button>
              </div>
            ) : (
              <div className="pl-6">
                <textarea
                  value={answer?.text ?? ''}
                  onChange={(e) => onGlobalChange(q.id, { text: e.target.value })}
                  placeholder={q.answer_type === 'photo' ? 'Photo URL or description...' : 'Type your answer...'}
                  rows={2}
                  className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
            )}
          </div>
        );
      })}

      {/* One-Time Questions */}
      {oneTimeQuestions.length > 0 && (
        <>
          <div className="flex items-center gap-2 pt-2">
            <div className="flex-1 border-t border-border" />
            <span className="text-xs font-medium text-orange-500 dark:text-orange-400 uppercase">
              One-Time Questions
            </span>
            <div className="flex-1 border-t border-border" />
          </div>
          {oneTimeQuestions.map((q) => (
            <div
              key={q.id}
              className="p-3 bg-orange-50 dark:bg-orange-900/10 border border-orange-200 dark:border-orange-800/30 rounded-lg space-y-2"
            >
              <div className="flex items-start gap-2">
                <MessageSquare className="h-4 w-4 text-orange-500 dark:text-orange-400 mt-0.5 shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                    {q.question_text}
                  </p>
                  {q.created_by_name && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                      Asked by {q.created_by_name}
                    </p>
                  )}
                </div>
              </div>
              <div className="pl-6">
                <textarea
                  value={oneTimeAnswerTexts.get(q.id) ?? ''}
                  onChange={(e) => onOneTimeChange(q.id, e.target.value)}
                  placeholder="Type your answer..."
                  rows={2}
                  className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-orange-500"
                />
              </div>
            </div>
          ))}
        </>
      )}

      {/* Actions */}
      <div className="flex items-center gap-2 pt-2">
        <Button variant="secondary" size="sm" icon={<ArrowLeft className="h-4 w-4" />} onClick={onCancel}>
          Cancel
        </Button>
        <Button
          size="sm"
          icon={<ArrowRight className="h-4 w-4" />}
          onClick={onNext}
          disabled={!allRequiredAnswered}
          className="ml-auto"
        >
          Review & Confirm
        </Button>
      </div>
    </div>
  );
}

// ── Step 2: Review & Confirm ────────────────────────────────────

function ReviewStep({
  globalQuestions,
  globalAnswers,
  oneTimeQuestions,
  oneTimeAnswerTexts,
  driveTimeMinutes,
  notes,
  gpsStatus,
  isSubmitting,
  onDriveTimeChange,
  onNotesChange,
  onBack,
  onSubmit,
}: {
  globalQuestions: ClockOutQuestionResponse[];
  globalAnswers: Map<number, { text?: string; bool?: boolean }>;
  oneTimeQuestions: OneTimeQuestionResponse[];
  oneTimeAnswerTexts: Map<number, string>;
  driveTimeMinutes: number;
  notes: string;
  gpsStatus: string;
  isSubmitting: boolean;
  onDriveTimeChange: (val: number) => void;
  onNotesChange: (val: string) => void;
  onBack: () => void;
  onSubmit: () => void;
}) {
  return (
    <div className="space-y-4">
      <div className="text-center mb-2">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          Review & Confirm
        </h3>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Verify your answers and clock out
        </p>
      </div>

      {/* GPS Status */}
      <div className="flex items-center gap-2 p-3 bg-gray-50 dark:bg-gray-800/50 border border-border rounded-lg">
        <MapPin className="h-4 w-4 text-gray-400 dark:text-gray-500" />
        <span className="text-sm text-gray-600 dark:text-gray-300">{gpsStatus}</span>
      </div>

      {/* Drive time */}
      <div className="flex items-center gap-3">
        <Clock className="h-4 w-4 text-gray-400 dark:text-gray-500" />
        <label className="text-sm text-gray-700 dark:text-gray-300">Drive time:</label>
        <input
          type="number"
          min={0}
          max={480}
          value={driveTimeMinutes}
          onChange={(e) => onDriveTimeChange(Number(e.target.value))}
          className="w-20 px-2 py-1.5 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
        />
        <span className="text-sm text-gray-500 dark:text-gray-400">minutes</span>
      </div>

      {/* Answer Summary */}
      <div className="space-y-2">
        <h4 className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
          Your Answers
        </h4>
        {globalQuestions.map((q) => {
          const answer = globalAnswers.get(q.id);
          return (
            <div key={q.id} className="flex items-start gap-2 text-sm">
              <span className="text-gray-500 dark:text-gray-400 shrink-0">•</span>
              <div className="flex-1">
                <span className="text-gray-700 dark:text-gray-300">{q.question_text}</span>
                <span className="text-gray-400 dark:text-gray-500"> → </span>
                {q.answer_type === 'yes_no' ? (
                  <span className={answer?.bool ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}>
                    {answer?.bool === true ? 'Yes' : answer?.bool === false ? 'No' : '—'}
                  </span>
                ) : (
                  <span className="text-gray-900 dark:text-gray-100 italic">
                    {answer?.text?.trim() || '—'}
                  </span>
                )}
              </div>
            </div>
          );
        })}
        {oneTimeQuestions.map((q) => (
          <div key={q.id} className="flex items-start gap-2 text-sm">
            <span className="text-orange-500 shrink-0">•</span>
            <div className="flex-1">
              <span className="text-gray-700 dark:text-gray-300">{q.question_text}</span>
              <span className="text-gray-400 dark:text-gray-500"> → </span>
              <span className="text-gray-900 dark:text-gray-100 italic">
                {oneTimeAnswerTexts.get(q.id)?.trim() || '—'}
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* Optional notes */}
      <div>
        <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">Notes (optional)</label>
        <textarea
          value={notes}
          onChange={(e) => onNotesChange(e.target.value)}
          placeholder="Any additional notes for today..."
          rows={2}
          className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>

      {/* Actions */}
      <div className="flex items-center gap-2 pt-2">
        <Button variant="secondary" size="sm" icon={<ArrowLeft className="h-4 w-4" />} onClick={onBack}>
          Back
        </Button>
        <Button
          variant="danger"
          size="sm"
          icon={isSubmitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
          onClick={onSubmit}
          disabled={isSubmitting}
          className="ml-auto"
        >
          {isSubmitting ? 'Clocking Out...' : 'Clock Out'}
        </Button>
      </div>
    </div>
  );
}

// ── Main Flow Component ─────────────────────────────────────────

export function ClockOutFlow({ jobId, laborEntryId, onComplete, onCancel }: ClockOutFlowProps) {
  const { clockOut } = useClockStore();

  // State
  const [step, setStep] = useState<'questions' | 'review'>('questions');
  const [globalAnswers, setGlobalAnswers] = useState<Map<number, { text?: string; bool?: boolean }>>(new Map());
  const [oneTimeAnswerTexts, setOneTimeAnswerTexts] = useState<Map<number, string>>(new Map());
  const [driveTimeMinutes, setDriveTimeMinutes] = useState(0);
  const [notes, setNotes] = useState('');
  const [gpsLat, setGpsLat] = useState<number | undefined>();
  const [gpsLng, setGpsLng] = useState<number | undefined>();
  const [gpsStatus, setGpsStatus] = useState('Requesting GPS...');
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Fetch clock-out bundle
  const { data: bundle, isLoading } = useQuery({
    queryKey: ['clock-out-bundle', jobId],
    queryFn: () => getClockOutBundle(jobId),
  });

  // Request GPS on mount
  useEffect(() => {
    if (!navigator.geolocation) {
      setGpsStatus('GPS not available');
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setGpsLat(pos.coords.latitude);
        setGpsLng(pos.coords.longitude);
        setGpsStatus(`GPS: ${pos.coords.latitude.toFixed(4)}, ${pos.coords.longitude.toFixed(4)}`);
      },
      () => setGpsStatus('GPS unavailable — will proceed without'),
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  }, []);

  // Submit clock-out
  async function handleSubmit() {
    setIsSubmitting(true);
    try {
      // Build responses array
      const responses: ClockOutResponseInput[] = [];
      for (const q of bundle?.global_questions ?? []) {
        const answer = globalAnswers.get(q.id);
        responses.push({
          question_id: q.id,
          answer_text: answer?.text ?? null,
          answer_bool: answer?.bool ?? null,
        });
      }

      // Build one-time answers
      const oneTimeAnswers: OneTimeAnswerInput[] = [];
      for (const q of bundle?.one_time_questions ?? []) {
        oneTimeAnswers.push({
          question_id: q.id,
          answer_text: oneTimeAnswerTexts.get(q.id) ?? null,
        });
      }

      await clockOut({
        labor_entry_id: laborEntryId,
        gps_lat: gpsLat,
        gps_lng: gpsLng,
        drive_time_minutes: driveTimeMinutes,
        notes: notes || undefined,
        responses,
        one_time_answers: oneTimeAnswers,
      });

      onComplete();
    } catch (err) {
      console.error('Clock-out failed:', err);
      setIsSubmitting(false);
    }
  }

  if (isLoading) return <PageSpinner label="Loading questions..." />;

  return (
    <div className="max-w-lg mx-auto">
      {step === 'questions' && (
        <QuestionStep
          globalQuestions={bundle?.global_questions ?? []}
          oneTimeQuestions={bundle?.one_time_questions ?? []}
          globalAnswers={globalAnswers}
          oneTimeAnswerTexts={oneTimeAnswerTexts}
          onGlobalChange={(qId, value) => {
            const next = new Map(globalAnswers);
            next.set(qId, { ...next.get(qId), ...value });
            setGlobalAnswers(next);
          }}
          onOneTimeChange={(qId, text) => {
            const next = new Map(oneTimeAnswerTexts);
            next.set(qId, text);
            setOneTimeAnswerTexts(next);
          }}
          onNext={() => setStep('review')}
          onCancel={onCancel}
        />
      )}

      {step === 'review' && (
        <ReviewStep
          globalQuestions={bundle?.global_questions ?? []}
          globalAnswers={globalAnswers}
          oneTimeQuestions={bundle?.one_time_questions ?? []}
          oneTimeAnswerTexts={oneTimeAnswerTexts}
          driveTimeMinutes={driveTimeMinutes}
          notes={notes}
          gpsStatus={gpsStatus}
          isSubmitting={isSubmitting}
          onDriveTimeChange={setDriveTimeMinutes}
          onNotesChange={setNotes}
          onBack={() => setStep('questions')}
          onSubmit={handleSubmit}
        />
      )}
    </div>
  );
}
