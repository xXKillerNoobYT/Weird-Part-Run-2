/**
 * QABoardPage — Q&A Escalation Board.
 *
 * Lists Q&A threads with filter bar (job/status/priority).
 * Thread detail shows the escalation timeline + message history
 * with context-dependent action buttons (escalate/answer/close/send to GC).
 */

import { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  MessageSquareWarning,
  Plus,
  ArrowUpRight,
  CheckCircle2,
  XCircle,
  Send,
  Filter,
  ChevronLeft,
  Loader2,
  ExternalLink,
  Phone,
  Mail,
  Building2,
} from 'lucide-react';
import { useAuthStore } from '../../../stores/auth-store';
import {
  getQAThreads,
  getQAThreadDetail,
  askQuestion,
  escalateThread,
  answerThread,
  closeThread,
  sendToGC,
} from '../../../api/chat';
import { getJobGCs, getGCContacts } from '../../../api/contacts';
import type {
  QAThreadResponse,
  QAStatus,
  QAPriority,
  AskQuestionRequest,
  JobGCResponse,
  EntityContactResponse,
  RFIResponse,
} from '../../../lib/types';
import { EscalationTimeline } from '../components/EscalationTimeline';
import { QAQuestionForm } from '../components/QAQuestionForm';

const STATUS_BADGES: Record<string, { label: string; className: string }> = {
  open: { label: 'Open', className: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' },
  escalated: { label: 'Escalated', className: 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300' },
  answered: { label: 'Answered', className: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300' },
  closed: { label: 'Closed', className: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400' },
  sent_to_gc: { label: 'Sent to GC', className: 'bg-purple-100 text-purple-700 dark:bg-purple-900/40 dark:text-purple-300' },
};

const PRIORITY_DOTS: Record<string, string> = {
  low: 'bg-gray-400',
  normal: 'bg-blue-500',
  high: 'bg-amber-500',
  urgent: 'bg-red-500',
};

const LEVEL_LABELS: Record<string, string> = {
  worker: 'Worker',
  lead: 'Lead',
  foreman: 'Foreman',
  supervisor: 'Supervisor',
  office: 'Office',
};

export default function QABoardPage() {
  const { user, hasPermission } = useAuthStore();
  const queryClient = useQueryClient();

  // ── State ────────────────────────────────────────────────────────
  const [filterStatus, setFilterStatus] = useState<QAStatus | ''>('');
  const [filterPriority, setFilterPriority] = useState<QAPriority | ''>('');
  const [selectedThreadId, setSelectedThreadId] = useState<number | null>(null);
  const [showNewForm, setShowNewForm] = useState(false);
  const [showFilters, setShowFilters] = useState(false);
  const [answerText, setAnswerText] = useState('');
  const [escalateComment, setEscalateComment] = useState('');
  // Send-to-GC flow state
  const [showSendToGC, setShowSendToGC] = useState(false);
  const [selectedGCId, setSelectedGCId] = useState<number | null>(null);
  const [selectedContactId, setSelectedContactId] = useState<number | null>(null);
  const [sendVia, setSendVia] = useState<'sms' | 'email'>('sms');

  // ── Data fetching ────────────────────────────────────────────────
  const { data: threads = [], isLoading: threadsLoading } = useQuery({
    queryKey: ['qa-threads', filterStatus, filterPriority],
    queryFn: () =>
      getQAThreads({
        status: filterStatus || undefined,
        priority: filterPriority || undefined,
        limit: 100,
      }),
    refetchInterval: 30_000,
  });

  const { data: threadDetail, isLoading: detailLoading } = useQuery({
    queryKey: ['qa-thread', selectedThreadId],
    queryFn: () => getQAThreadDetail(selectedThreadId!),
    enabled: selectedThreadId != null,
    refetchInterval: 15_000,
  });

  const thread = threadDetail?.thread;

  // ── Mutations ────────────────────────────────────────────────────
  const askMutation = useMutation({
    mutationFn: (body: AskQuestionRequest) => askQuestion(body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['qa-threads'] });
      setShowNewForm(false);
    },
  });

  const escalateMutation = useMutation({
    mutationFn: (threadId: number) =>
      escalateThread(threadId, { comment: escalateComment || undefined }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['qa-threads'] });
      queryClient.invalidateQueries({ queryKey: ['qa-thread', selectedThreadId] });
      setEscalateComment('');
    },
  });

  const answerMutation = useMutation({
    mutationFn: (threadId: number) =>
      answerThread(threadId, { answer: answerText }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['qa-threads'] });
      queryClient.invalidateQueries({ queryKey: ['qa-thread', selectedThreadId] });
      setAnswerText('');
    },
  });

  const closeMutation = useMutation({
    mutationFn: (threadId: number) => closeThread(threadId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['qa-threads'] });
      queryClient.invalidateQueries({ queryKey: ['qa-thread', selectedThreadId] });
    },
  });

  const sendToGCMutation = useMutation({
    mutationFn: ({ threadId, gcContactId, via }: { threadId: number; gcContactId: number; via: 'sms' | 'email' }) =>
      sendToGC(threadId, { gc_contact_id: gcContactId, via }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['qa-threads'] });
      queryClient.invalidateQueries({ queryKey: ['qa-thread', selectedThreadId] });
      setShowSendToGC(false);
      setSelectedGCId(null);
      setSelectedContactId(null);
    },
  });

  // Fetch GCs linked to this thread's job (for "Send to GC" picker)
  const { data: jobGCs = [] } = useQuery({
    queryKey: ['job-gcs', thread?.job_id],
    queryFn: () => getJobGCs(thread!.job_id!),
    enabled: showSendToGC && thread?.job_id != null,
  });

  // Fetch contacts for selected GC
  const { data: gcContacts = [] } = useQuery({
    queryKey: ['gc-contacts', selectedGCId],
    queryFn: () => getGCContacts(selectedGCId!),
    enabled: selectedGCId != null,
  });

  // ── Handlers ─────────────────────────────────────────────────────
  const handleSelectThread = useCallback((threadId: number) => {
    setSelectedThreadId(threadId);
    setShowNewForm(false);
    setAnswerText('');
    setEscalateComment('');
    setShowSendToGC(false);
    setSelectedGCId(null);
    setSelectedContactId(null);
  }, []);

  const canEscalate = thread && ['open', 'escalated'].includes(thread.status) && hasPermission('escalate_qa');
  const canAnswer = thread && ['open', 'escalated', 'sent_to_gc'].includes(thread.status) && hasPermission('answer_qa');
  const canClose = thread && thread.status !== 'closed';
  const canAsk = hasPermission('ask_qa');
  const canSendToGC = thread && ['open', 'escalated'].includes(thread.status)
    && thread.current_level === 'office' && hasPermission('send_rfi');

  if (!user) return null;

  // ── Render ───────────────────────────────────────────────────────
  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3 px-4 py-3 border-b border-border bg-surface">
        <div className="flex items-center gap-2">
          {selectedThreadId != null && (
            <button
              onClick={() => setSelectedThreadId(null)}
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 lg:hidden min-h-[44px] min-w-[44px] flex items-center justify-center"
            >
              <ChevronLeft className="h-5 w-5 text-gray-500" />
            </button>
          )}
          <MessageSquareWarning className="h-5 w-5 text-amber-500" />
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            Q&A Board
          </h2>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowFilters(!showFilters)}
            className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 border border-border"
            title="Filter"
          >
            <Filter className="h-4 w-4 text-gray-500" />
          </button>
          {canAsk && (
            <button
              onClick={() => { setShowNewForm(true); setSelectedThreadId(null); }}
              className="flex items-center gap-1.5 px-3 py-2 bg-primary-600 text-white text-sm rounded-lg hover:bg-primary-700"
            >
              <Plus className="h-4 w-4" />
              <span className="hidden sm:inline">Ask Question</span>
            </button>
          )}
        </div>
      </div>

      {/* Filter bar */}
      {showFilters && (
        <div className="flex items-center gap-3 px-4 py-2 border-b border-border bg-surface-secondary flex-wrap">
          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value as QAStatus | '')}
            className="rounded-lg border border-border bg-surface px-2 py-1 text-sm"
          >
            <option value="">All Statuses</option>
            <option value="open">Open</option>
            <option value="escalated">Escalated</option>
            <option value="answered">Answered</option>
            <option value="closed">Closed</option>
            <option value="sent_to_gc">Sent to GC</option>
          </select>
          <select
            value={filterPriority}
            onChange={(e) => setFilterPriority(e.target.value as QAPriority | '')}
            className="rounded-lg border border-border bg-surface px-2 py-1 text-sm"
          >
            <option value="">All Priorities</option>
            <option value="low">Low</option>
            <option value="normal">Normal</option>
            <option value="high">High</option>
            <option value="urgent">Urgent</option>
          </select>
        </div>
      )}

      {/* Content area */}
      <div className="flex-1 flex overflow-hidden">
        {/* Thread list */}
        <div
          className={`w-full lg:w-[380px] xl:w-[420px] lg:flex-shrink-0 border-r border-border overflow-y-auto ${selectedThreadId != null || showNewForm ? 'hidden lg:block' : ''
            }`}
        >
          {threadsLoading ? (
            <div className="flex items-center justify-center py-12">
              <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
            </div>
          ) : threads.length === 0 ? (
            <div className="text-center py-12 px-4">
              <MessageSquareWarning className="h-8 w-8 text-gray-300 mx-auto mb-2" />
              <p className="text-sm text-gray-500 dark:text-gray-400">No Q&A threads found</p>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {threads.map((t) => (
                <ThreadCard
                  key={t.id}
                  thread={t}
                  isSelected={t.id === selectedThreadId}
                  onClick={() => handleSelectThread(t.id)}
                />
              ))}
            </div>
          )}
        </div>

        {/* Detail / Form panel */}
        <div
          className={`flex-1 min-w-0 overflow-y-auto ${selectedThreadId != null || showNewForm ? '' : 'hidden lg:block'
            }`}
        >
          {showNewForm ? (
            <div className="max-w-2xl mx-auto px-4 py-6">
              <QAQuestionForm
                onSubmit={(body) => askMutation.mutate(body)}
                onCancel={() => setShowNewForm(false)}
                isSubmitting={askMutation.isPending}
              />
            </div>
          ) : selectedThreadId != null && threadDetail ? (
            <div className="px-4 py-4 space-y-4">
              {/* Thread header */}
              <div>
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                    {thread?.subject}
                  </h3>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    {thread && (
                      <>
                        <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_BADGES[thread.status]?.className ?? STATUS_BADGES.open.className
                          }`}>
                          {STATUS_BADGES[thread.status]?.label ?? thread.status}
                        </span>
                        <span className="flex items-center gap-1 text-xs text-gray-500">
                          <span className={`w-2 h-2 rounded-full ${PRIORITY_DOTS[thread.priority] ?? PRIORITY_DOTS.normal}`} />
                          {thread.priority}
                        </span>
                      </>
                    )}
                  </div>
                </div>
                {thread && (
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
                    {thread.job_number && (
                      <span>Job: {thread.job_number}</span>
                    )}
                    <span>Asked by: {thread.asker_name || `User #${thread.asked_by}`}</span>
                    <span>Level: {LEVEL_LABELS[thread.current_level] || thread.current_level}</span>
                    {thread.assigned_name && (
                      <span>Assigned: {thread.assigned_name}</span>
                    )}
                  </div>
                )}
              </div>

              {/* Escalation timeline */}
              {threadDetail.timeline.length > 0 && (
                <div className="bg-surface-secondary rounded-lg px-4 py-2">
                  <EscalationTimeline
                    timeline={threadDetail.timeline}
                    currentLevel={thread?.current_level as any}
                  />
                </div>
              )}

              {/* RFI info card (when thread has been sent to GC) */}
              {threadDetail.rfi && (
                <RFIInfoCard rfi={threadDetail.rfi} />
              )}

              {/* Messages */}
              <div className="space-y-3">
                <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300">
                  Messages ({threadDetail.messages.length})
                </h4>
                {threadDetail.messages.map((msg) => (
                  <div
                    key={msg.id}
                    className="bg-surface border border-border rounded-lg px-3 py-2"
                  >
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs font-medium text-gray-700 dark:text-gray-300">
                        {msg.sender_name || `User #${msg.sender_id}`}
                        {msg.qa_level && (
                          <span className="ml-1 text-gray-400">
                            ({LEVEL_LABELS[msg.qa_level] || msg.qa_level})
                          </span>
                        )}
                      </span>
                      <span className="text-[10px] text-gray-400">
                        {msg.created_at
                          ? new Date(msg.created_at).toLocaleString([], {
                            month: 'short', day: 'numeric',
                            hour: '2-digit', minute: '2-digit',
                          })
                          : ''}
                      </span>
                    </div>
                    <p className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap">
                      {msg.content}
                    </p>
                  </div>
                ))}
              </div>

              {/* Action buttons */}
              {thread && thread.status !== 'closed' && (
                <div className="border-t border-border pt-4 space-y-3">
                  {/* Answer */}
                  {canAnswer && (
                    <div className="space-y-2">
                      <textarea
                        value={answerText}
                        onChange={(e) => setAnswerText(e.target.value)}
                        placeholder="Type your answer..."
                        rows={3}
                        className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm resize-y focus:ring-2 focus:ring-primary-500"
                      />
                      <button
                        onClick={() => answerMutation.mutate(thread.id)}
                        disabled={!answerText.trim() || answerMutation.isPending}
                        className="flex items-center gap-1.5 px-3 py-2 bg-green-600 text-white text-sm rounded-lg hover:bg-green-700 disabled:opacity-50"
                      >
                        {answerMutation.isPending ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <CheckCircle2 className="h-4 w-4" />
                        )}
                        Answer
                      </button>
                    </div>
                  )}

                  {/* Escalate + Close */}
                  <div className="flex items-center gap-2 flex-wrap">
                    {canEscalate && (
                      <div className="flex items-center gap-2">
                        <input
                          type="text"
                          value={escalateComment}
                          onChange={(e) => setEscalateComment(e.target.value)}
                          placeholder="Comment (optional)..."
                          className="rounded-lg border border-border bg-surface px-2 py-1.5 text-sm w-48"
                        />
                        <button
                          onClick={() => escalateMutation.mutate(thread.id)}
                          disabled={escalateMutation.isPending}
                          className="flex items-center gap-1.5 px-3 py-2 bg-amber-600 text-white text-sm rounded-lg hover:bg-amber-700 disabled:opacity-50"
                        >
                          {escalateMutation.isPending ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            <ArrowUpRight className="h-4 w-4" />
                          )}
                          Escalate
                        </button>
                      </div>
                    )}

                    {canClose && (
                      <button
                        onClick={() => closeMutation.mutate(thread.id)}
                        disabled={closeMutation.isPending}
                        className="flex items-center gap-1.5 px-3 py-2 border border-border text-sm rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-50"
                      >
                        {closeMutation.isPending ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <XCircle className="h-4 w-4 text-gray-500" />
                        )}
                        Close
                      </button>
                    )}

                    {canSendToGC && (
                      <button
                        onClick={() => setShowSendToGC(!showSendToGC)}
                        className="flex items-center gap-1.5 px-3 py-2 bg-purple-600 text-white text-sm rounded-lg hover:bg-purple-700"
                      >
                        <Send className="h-4 w-4" />
                        <span className="hidden sm:inline">Send to GC</span>
                      </button>
                    )}
                  </div>

                  {/* Send to GC contact picker panel */}
                  {showSendToGC && canSendToGC && (
                    <div className="bg-purple-50 dark:bg-purple-900/20 border border-purple-200 dark:border-purple-800 rounded-lg p-4 space-y-3">
                      <h5 className="text-sm font-medium text-purple-800 dark:text-purple-300 flex items-center gap-1.5">
                        <Building2 className="h-4 w-4" />
                        Send to General Contractor
                      </h5>

                      {/* Step 1: Pick GC */}
                      <div>
                        <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 mb-1">
                          Select GC
                        </label>
                        {jobGCs.length === 0 ? (
                          <p className="text-xs text-gray-500 italic">
                            No GCs linked to this job. Link a GC to the job first.
                          </p>
                        ) : (
                          <select
                            value={selectedGCId ?? ''}
                            onChange={(e) => {
                              const id = e.target.value ? Number(e.target.value) : null;
                              setSelectedGCId(id);
                              setSelectedContactId(null);
                            }}
                            className="w-full rounded-lg border border-border bg-surface px-2 py-1.5 text-sm"
                          >
                            <option value="">Choose a GC...</option>
                            {jobGCs.map((gc: JobGCResponse) => (
                              <option key={gc.gc_id} value={gc.gc_id}>
                                {gc.company_name} ({gc.gc_code})
                              </option>
                            ))}
                          </select>
                        )}
                      </div>

                      {/* Step 2: Pick contact person at GC */}
                      {selectedGCId && (
                        <div>
                          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 mb-1">
                            Contact Person
                          </label>
                          {gcContacts.length === 0 ? (
                            <p className="text-xs text-gray-500 italic">
                              No contacts for this GC. Add a contact first.
                            </p>
                          ) : (
                            <select
                              value={selectedContactId ?? ''}
                              onChange={(e) => setSelectedContactId(e.target.value ? Number(e.target.value) : null)}
                              className="w-full rounded-lg border border-border bg-surface px-2 py-1.5 text-sm"
                            >
                              <option value="">Choose a contact...</option>
                              {gcContacts.map((c: EntityContactResponse) => (
                                <option key={c.id} value={c.id}>
                                  {c.first_name} {c.last_name} — {c.role}
                                  {c.phone ? ` (${c.phone})` : ''}
                                </option>
                              ))}
                            </select>
                          )}
                        </div>
                      )}

                      {/* Step 3: Choose send method */}
                      {selectedContactId && (
                        <div className="flex items-center gap-4">
                          <label className="flex items-center gap-1.5 text-sm cursor-pointer">
                            <input
                              type="radio"
                              name="send-via"
                              value="sms"
                              checked={sendVia === 'sms'}
                              onChange={() => setSendVia('sms')}
                              className="accent-purple-600"
                            />
                            <Phone className="h-3.5 w-3.5 text-gray-500" />
                            SMS
                          </label>
                          <label className="flex items-center gap-1.5 text-sm cursor-pointer">
                            <input
                              type="radio"
                              name="send-via"
                              value="email"
                              checked={sendVia === 'email'}
                              onChange={() => setSendVia('email')}
                              className="accent-purple-600"
                            />
                            <Mail className="h-3.5 w-3.5 text-gray-500" />
                            Email
                          </label>
                        </div>
                      )}

                      {/* Step 4: Send button */}
                      {selectedContactId && (
                        <button
                          onClick={() => sendToGCMutation.mutate({
                            threadId: thread.id,
                            gcContactId: selectedContactId,
                            via: sendVia,
                          })}
                          disabled={sendToGCMutation.isPending}
                          className="flex items-center gap-1.5 px-4 py-2 bg-purple-600 text-white text-sm rounded-lg hover:bg-purple-700 disabled:opacity-50"
                        >
                          {sendToGCMutation.isPending ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            <ExternalLink className="h-4 w-4" />
                          )}
                          Create RFI &amp; Send
                        </button>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          ) : detailLoading ? (
            <div className="flex items-center justify-center h-full">
              <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center h-full text-center px-6">
              <div className="w-16 h-16 rounded-full bg-gray-100 dark:bg-gray-800 flex items-center justify-center mb-4">
                <MessageSquareWarning className="h-8 w-8 text-gray-400" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1">
                Select a thread
              </h3>
              <p className="text-sm text-gray-500 dark:text-gray-400 max-w-xs">
                Choose a Q&A thread from the list to view details, or ask a new question.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}


// ── Thread card sub-component ──────────────────────────────────────

function ThreadCard({
  thread,
  isSelected,
  onClick,
}: {
  thread: QAThreadResponse;
  isSelected: boolean;
  onClick: () => void;
}) {
  const badge = STATUS_BADGES[thread.status] ?? STATUS_BADGES.open;
  const priorityDot = PRIORITY_DOTS[thread.priority] ?? PRIORITY_DOTS.normal;

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors ${isSelected ? 'bg-primary-50 dark:bg-primary-900/20 border-l-2 border-primary-500' : ''
        }`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5 mb-0.5">
            <span className={`w-2 h-2 rounded-full flex-shrink-0 ${priorityDot}`} />
            <h4 className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
              {thread.subject}
            </h4>
          </div>
          <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
            {thread.job_number && <span>{thread.job_number}</span>}
            <span>{thread.asker_name || `User #${thread.asked_by}`}</span>
            <span>{LEVEL_LABELS[thread.current_level] || thread.current_level}</span>
          </div>
        </div>
        <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium flex-shrink-0 ${badge.className}`}>
          {badge.label}
        </span>
      </div>
      {thread.created_at && (
        <p className="text-[10px] text-gray-400 mt-1">
          {new Date(thread.created_at).toLocaleDateString([], {
            month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
          })}
        </p>
      )}
    </button>
  );
}


// ── RFI info card sub-component ────────────────────────────────────

const RFI_STATUS_BADGES: Record<string, { label: string; className: string }> = {
  draft: { label: 'Draft', className: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400' },
  sent_text: { label: 'Sent (SMS)', className: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' },
  sent_email: { label: 'Sent (Email)', className: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' },
  sent_app: { label: 'Sent (App)', className: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' },
  answered: { label: 'Answered', className: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300' },
  closed: { label: 'Closed', className: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400' },
};

function RFIInfoCard({ rfi }: { rfi: RFIResponse }) {
  const badge = RFI_STATUS_BADGES[rfi.status] ?? RFI_STATUS_BADGES.draft;

  return (
    <div className="bg-purple-50 dark:bg-purple-900/20 border border-purple-200 dark:border-purple-800 rounded-lg p-4 space-y-2">
      <div className="flex items-center justify-between flex-wrap gap-2">
        <h5 className="text-sm font-medium text-purple-800 dark:text-purple-300 flex items-center gap-1.5">
          <ExternalLink className="h-4 w-4" />
          RFI #{rfi.id} — {rfi.subject}
        </h5>
        <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${badge.className}`}>
          {badge.label}
        </span>
      </div>

      <div className="flex items-center gap-4 text-xs text-gray-600 dark:text-gray-400 flex-wrap">
        {rfi.gc_name && (
          <span className="flex items-center gap-1">
            <Building2 className="h-3 w-3" />
            {rfi.gc_name}
          </span>
        )}
        {rfi.gc_phone && (
          <a href={`sms:${rfi.gc_phone}`} className="flex items-center gap-1 text-primary-600 hover:underline">
            <Phone className="h-3 w-3" />
            {rfi.gc_phone}
          </a>
        )}
        {rfi.gc_email && (
          <a href={`mailto:${rfi.gc_email}`} className="flex items-center gap-1 text-primary-600 hover:underline">
            <Mail className="h-3 w-3" />
            {rfi.gc_email}
          </a>
        )}
      </div>

      {rfi.sent_at && (
        <p className="text-xs text-gray-500">
          Sent {rfi.sent_via ? `via ${rfi.sent_via}` : ''} on{' '}
          {new Date(rfi.sent_at).toLocaleDateString([], {
            month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
          })}
        </p>
      )}

      {rfi.response_text && (
        <div className="mt-2 p-3 bg-white dark:bg-gray-800 rounded border border-green-200 dark:border-green-800">
          <p className="text-xs font-medium text-green-700 dark:text-green-400 mb-1">
            GC Response:
          </p>
          <p className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap">
            {rfi.response_text}
          </p>
          {rfi.responded_at && (
            <p className="text-[10px] text-gray-400 mt-1">
              {new Date(rfi.responded_at).toLocaleDateString([], {
                month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
              })}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
