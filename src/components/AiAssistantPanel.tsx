/**
 * AiAssistantPanel — Floating AI assistant accessible from every page.
 *
 * Features:
 *   1. Floating action button (bottom-right) with anomaly badge count
 *   2. Slide-out panel with three tabs: Chat, Anomalies, Predictions
 *   3. Chat tab: ephemeral conversation (not persisted), context-aware quick prompts
 *   4. Anomalies tab: dismissible warnings from nightly AI scans
 *   5. Predictions tab: ordering suggestions based on historical usage
 *   6. Context-aware: prompts change based on current page (uses useLocation)
 *
 * The panel is rendered inside AuthGate but outside AppShell so it floats
 * over all content. Conversations are held in React state only — fully ephemeral.
 */

import { useState, useRef, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
    Bot, X, Send, Loader2, AlertTriangle, ShoppingCart,
    MessageSquare, RefreshCw, ChevronDown, Sparkles, Trash2,
} from 'lucide-react';
import { useAuthStore } from '../stores/auth-store';
import {
    askAi,
    getAnomalies,
    getPredictions,
    getAiPrompts,
    getAnomalyCount,
    dismissAnomaly,
    refreshAnomalies,
    refreshPredictions,
} from '../api/ai';
import { getAllSettings } from '../api/settings';
import type { AiCachedResult } from '../api/ai';


// ── Helpers ──────────────────────────────────────────────────────

/** Map the current URL path to a page context string the backend understands. */
function getPageContext(pathname: string): string {
    if (pathname.startsWith('/dashboard')) return 'dashboard';
    if (pathname.match(/^\/jobs\/\d+/)) return 'job_detail';
    if (pathname.startsWith('/jobs')) return 'jobs';
    if (pathname.startsWith('/parts')) return 'parts';
    if (pathname.startsWith('/warehouse')) return 'warehouse';
    if (pathname.startsWith('/orders')) return 'orders';
    if (pathname.startsWith('/scheduling')) return 'schedule';
    if (pathname.startsWith('/people')) return 'people';
    if (pathname.startsWith('/office/spending')) return 'costs';
    if (pathname.startsWith('/trucks')) return 'fleet';
    if (pathname.startsWith('/reports')) return 'reports';
    return 'default';
}

/** Severity → color classes */
function severityColor(severity?: string) {
    switch (severity) {
        case 'critical': return 'border-red-300 bg-red-50 dark:border-red-700 dark:bg-red-900/20';
        case 'warning': return 'border-amber-300 bg-amber-50 dark:border-amber-700 dark:bg-amber-900/20';
        default: return 'border-blue-200 bg-blue-50 dark:border-blue-700 dark:bg-blue-900/20';
    }
}

function severityBadge(severity?: string) {
    switch (severity) {
        case 'critical': return 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300';
        case 'warning': return 'bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300';
        default: return 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300';
    }
}


// ── Types ────────────────────────────────────────────────────────

interface ChatMessage {
    role: 'user' | 'assistant';
    content: string;
    toolCalls?: number;
}

type PanelTab = 'chat' | 'anomalies' | 'predictions';


// ── Component ────────────────────────────────────────────────────

export function AiAssistantPanel() {
    const { hasPermission } = useAuthStore();
    const location = useLocation();
    const queryClient = useQueryClient();
    const pageContext = getPageContext(location.pathname);

    // ── State ──
    const [isOpen, setIsOpen] = useState(false);
    const [activeTab, setActiveTab] = useState<PanelTab>('chat');
    const [messages, setMessages] = useState<ChatMessage[]>([]);
    const [input, setInput] = useState('');
    const [isAsking, setIsAsking] = useState(false);
    const [isRefreshingAnomalies, setIsRefreshingAnomalies] = useState(false);
    const [isRefreshingPredictions, setIsRefreshingPredictions] = useState(false);
    const messagesEndRef = useRef<HTMLDivElement>(null);
    const inputRef = useRef<HTMLTextAreaElement>(null);

    // ── Check if AI is enabled via settings ──
    const { data: allSettings } = useQuery({
        queryKey: ['all-settings'],
        queryFn: getAllSettings,
        staleTime: 60_000,
    });

    const aiSettings = (allSettings?.ai ?? {}) as Record<string, string>;
    const aiEnabled = aiSettings.ai_enabled === 'true';
    const nlQueriesEnabled = aiSettings.ai_nl_queries === 'true';
    const anomalyEnabled = aiSettings.ai_anomaly_detection === 'true';
    const predictiveEnabled = aiSettings.ai_predictive_ordering === 'true';

    // Don't render anything if AI is disabled or user lacks permission
    const canSeeAi = hasPermission('use_ai') && aiEnabled;

    // ── Data queries (only when panel is visible) ──
    const { data: anomalyCount = 0 } = useQuery({
        queryKey: ['ai-anomaly-count'],
        queryFn: getAnomalyCount,
        enabled: canSeeAi,
        staleTime: 5 * 60_000,
        refetchInterval: 5 * 60_000, // Refresh badge every 5 minutes
    });

    const { data: anomalies = [], refetch: refetchAnomalies } = useQuery({
        queryKey: ['ai-anomalies'],
        queryFn: () => getAnomalies(false),
        enabled: canSeeAi && isOpen && activeTab === 'anomalies',
        staleTime: 60_000,
    });

    const { data: predictions = [], refetch: refetchPredictions } = useQuery({
        queryKey: ['ai-predictions'],
        queryFn: getPredictions,
        enabled: canSeeAi && isOpen && activeTab === 'predictions',
        staleTime: 60_000,
    });

    const { data: promptsData } = useQuery({
        queryKey: ['ai-prompts', pageContext],
        queryFn: () => getAiPrompts(pageContext),
        enabled: canSeeAi && isOpen && activeTab === 'chat' && nlQueriesEnabled,
        staleTime: Infinity, // Prompts don't change unless page changes
    });

    const suggestedPrompts = promptsData?.prompts ?? [];

    // ── Auto-scroll chat to bottom ──
    useEffect(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [messages]);

    // ── Focus input when panel opens ──
    useEffect(() => {
        if (isOpen && activeTab === 'chat') {
            setTimeout(() => inputRef.current?.focus(), 200);
        }
    }, [isOpen, activeTab]);

    // ── Send message ──
    const handleSend = useCallback(async (question?: string) => {
        const q = (question ?? input).trim();
        if (!q || isAsking) return;

        const userMsg: ChatMessage = { role: 'user', content: q };
        setMessages(prev => [...prev, userMsg]);
        setInput('');
        setIsAsking(true);

        try {
            // Build conversation history for context (last 10 messages max)
            const history = [...messages, userMsg]
                .slice(-10)
                .map(m => ({ role: m.role, content: m.content }));

            const result = await askAi({
                question: q,
                conversation_history: history,
                page_context: pageContext,
            });

            setMessages(prev => [...prev, {
                role: 'assistant',
                content: result.answer,
                toolCalls: result.tool_calls_made,
            }]);
        } catch (err: unknown) {
            const errMsg = err instanceof Error ? err.message : 'Failed to get response';
            setMessages(prev => [...prev, {
                role: 'assistant',
                content: `⚠️ Error: ${errMsg}\n\nMake sure LM Studio is running and a model is loaded.`,
            }]);
        } finally {
            setIsAsking(false);
        }
    }, [input, isAsking, messages, pageContext]);

    // ── Keyboard handling for textarea ──
    const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            handleSend();
        }
    };

    // ── Dismiss anomaly ──
    const handleDismiss = async (id: number) => {
        try {
            await dismissAnomaly(id);
            await refetchAnomalies();
            queryClient.invalidateQueries({ queryKey: ['ai-anomaly-count'] });
        } catch {
            // Silently fail — the anomaly stays visible
        }
    };

    // ── Refresh anomalies ──
    const handleRefreshAnomalies = async () => {
        setIsRefreshingAnomalies(true);
        try {
            await refreshAnomalies();
            await refetchAnomalies();
            queryClient.invalidateQueries({ queryKey: ['ai-anomaly-count'] });
        } catch {
            // ignore
        } finally {
            setIsRefreshingAnomalies(false);
        }
    };

    // ── Refresh predictions ──
    const handleRefreshPredictions = async () => {
        setIsRefreshingPredictions(true);
        try {
            await refreshPredictions(30);
            await refetchPredictions();
        } catch {
            // ignore
        } finally {
            setIsRefreshingPredictions(false);
        }
    };

    // ── Clear conversation ──
    const clearChat = () => {
        setMessages([]);
        inputRef.current?.focus();
    };

    // Don't render if AI is off or user lacks permission
    if (!canSeeAi) return null;

    return (
        <>
            {/* ── Floating Action Button ─────────────────────────────── */}
            {!isOpen && (
                <button
                    onClick={() => setIsOpen(true)}
                    className="fixed bottom-5 right-5 z-50 flex h-14 w-14 items-center justify-center rounded-full bg-violet-600 text-white shadow-lg hover:bg-violet-700 active:bg-violet-800 transition-all hover:scale-105 focus:outline-none focus:ring-2 focus:ring-violet-400 focus:ring-offset-2"
                    aria-label="Open AI Assistant"
                >
                    <Bot className="h-6 w-6" />
                    {/* Badge */}
                    {anomalyCount > 0 && (
                        <span className="absolute -top-1 -right-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white px-1">
                            {anomalyCount > 99 ? '99+' : anomalyCount}
                        </span>
                    )}
                </button>
            )}

            {/* ── Slide-out Panel ────────────────────────────────────── */}
            {isOpen && (
                <div className="fixed bottom-0 right-0 z-50 flex flex-col w-full sm:w-[420px] h-[min(85vh,680px)] sm:bottom-4 sm:right-4 sm:rounded-2xl bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 shadow-2xl overflow-hidden">

                    {/* Header */}
                    <div className="flex items-center justify-between px-4 py-3 bg-violet-600 text-white flex-shrink-0">
                        <div className="flex items-center gap-2.5">
                            <Bot className="h-5 w-5" />
                            <span className="font-semibold text-sm">AI Assistant</span>
                            <span className="text-[10px] bg-violet-500 px-1.5 py-0.5 rounded-full opacity-80">
                                Local LLM
                            </span>
                        </div>
                        <button
                            onClick={() => setIsOpen(false)}
                            className="p-1 rounded-lg hover:bg-violet-500 transition-colors"
                            aria-label="Close AI panel"
                        >
                            <X className="h-4.5 w-4.5" />
                        </button>
                    </div>

                    {/* Tab Bar */}
                    <div className="flex border-b border-gray-200 dark:border-gray-700 flex-shrink-0">
                        <TabButton
                            active={activeTab === 'chat'}
                            onClick={() => setActiveTab('chat')}
                            icon={<MessageSquare className="h-3.5 w-3.5" />}
                            label="Chat"
                            disabled={!nlQueriesEnabled}
                        />
                        <TabButton
                            active={activeTab === 'anomalies'}
                            onClick={() => setActiveTab('anomalies')}
                            icon={<AlertTriangle className="h-3.5 w-3.5" />}
                            label="Anomalies"
                            badge={anomalyCount > 0 ? anomalyCount : undefined}
                            disabled={!anomalyEnabled}
                        />
                        <TabButton
                            active={activeTab === 'predictions'}
                            onClick={() => setActiveTab('predictions')}
                            icon={<ShoppingCart className="h-3.5 w-3.5" />}
                            label="Predictions"
                            disabled={!predictiveEnabled}
                        />
                    </div>

                    {/* Tab Content */}
                    <div className="flex-1 overflow-y-auto min-h-0">
                        {activeTab === 'chat' && nlQueriesEnabled && (
                            <ChatTab
                                messages={messages}
                                suggestedPrompts={suggestedPrompts}
                                isAsking={isAsking}
                                onSendPrompt={(p) => handleSend(p)}
                                onClear={clearChat}
                                messagesEndRef={messagesEndRef}
                            />
                        )}
                        {activeTab === 'chat' && !nlQueriesEnabled && (
                            <DisabledFeature feature="Natural Language Queries" />
                        )}
                        {activeTab === 'anomalies' && anomalyEnabled && (
                            <AnomaliesTab
                                anomalies={anomalies}
                                onDismiss={handleDismiss}
                                onRefresh={handleRefreshAnomalies}
                                isRefreshing={isRefreshingAnomalies}
                            />
                        )}
                        {activeTab === 'anomalies' && !anomalyEnabled && (
                            <DisabledFeature feature="Anomaly Detection" />
                        )}
                        {activeTab === 'predictions' && predictiveEnabled && (
                            <PredictionsTab
                                predictions={predictions}
                                onRefresh={handleRefreshPredictions}
                                isRefreshing={isRefreshingPredictions}
                            />
                        )}
                        {activeTab === 'predictions' && !predictiveEnabled && (
                            <DisabledFeature feature="Predictive Ordering" />
                        )}
                    </div>

                    {/* Input area (chat tab only) */}
                    {activeTab === 'chat' && nlQueriesEnabled && (
                        <div className="flex-shrink-0 border-t border-gray-200 dark:border-gray-700 p-3 bg-gray-50 dark:bg-gray-800/50">
                            <div className="flex gap-2">
                                <textarea
                                    ref={inputRef}
                                    value={input}
                                    onChange={(e) => setInput(e.target.value)}
                                    onKeyDown={handleKeyDown}
                                    placeholder="Ask about your data…"
                                    rows={1}
                                    disabled={isAsking}
                                    className="flex-1 resize-none rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-violet-400 focus:border-violet-400 disabled:opacity-50"
                                    style={{ maxHeight: '120px' }}
                                    onInput={(e) => {
                                        const target = e.target as HTMLTextAreaElement;
                                        target.style.height = 'auto';
                                        target.style.height = Math.min(target.scrollHeight, 120) + 'px';
                                    }}
                                />
                                <button
                                    onClick={() => handleSend()}
                                    disabled={!input.trim() || isAsking}
                                    className="flex h-10 w-10 items-center justify-center rounded-xl bg-violet-600 text-white hover:bg-violet-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex-shrink-0 self-end"
                                    aria-label="Send"
                                >
                                    {isAsking ? (
                                        <Loader2 className="h-4 w-4 animate-spin" />
                                    ) : (
                                        <Send className="h-4 w-4" />
                                    )}
                                </button>
                            </div>
                        </div>
                    )}
                </div>
            )}
        </>
    );
}


// ═══════════════════════════════════════════════════════════════
// Sub-components
// ═══════════════════════════════════════════════════════════════

function TabButton({
    active, onClick, icon, label, badge, disabled,
}: {
    active: boolean;
    onClick: () => void;
    icon: React.ReactNode;
    label: string;
    badge?: number;
    disabled?: boolean;
}) {
    return (
        <button
            onClick={onClick}
            disabled={disabled}
            className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 text-xs font-medium transition-colors relative ${disabled
                    ? 'text-gray-300 dark:text-gray-600 cursor-not-allowed'
                    : active
                        ? 'text-violet-600 dark:text-violet-400 border-b-2 border-violet-600 dark:border-violet-400'
                        : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                }`}
        >
            {icon}
            <span className="hidden sm:inline">{label}</span>
            {badge != null && badge > 0 && (
                <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-red-500 text-[9px] font-bold text-white px-1">
                    {badge > 99 ? '99+' : badge}
                </span>
            )}
        </button>
    );
}


// ── Chat Tab ─────────────────────────────────────────────────────

function ChatTab({
    messages, suggestedPrompts, isAsking, onSendPrompt, onClear, messagesEndRef,
}: {
    messages: ChatMessage[];
    suggestedPrompts: string[];
    isAsking: boolean;
    onSendPrompt: (prompt: string) => void;
    onClear: () => void;
    messagesEndRef: React.RefObject<HTMLDivElement | null>;
}) {
    if (messages.length === 0) {
        return (
            <div className="p-4 space-y-4">
                {/* Welcome */}
                <div className="text-center py-6">
                    <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-violet-100 dark:bg-violet-900/30">
                        <Sparkles className="h-6 w-6 text-violet-500 dark:text-violet-400" />
                    </div>
                    <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-1">
                        Ask me anything
                    </h3>
                    <p className="text-xs text-gray-500 dark:text-gray-400 max-w-[260px] mx-auto">
                        I can query your database, summarize reports, and answer questions about jobs, parts, labor, and more.
                    </p>
                </div>

                {/* Suggested prompts */}
                {suggestedPrompts.length > 0 && (
                    <div className="space-y-1.5">
                        <p className="text-[10px] font-medium text-gray-400 dark:text-gray-500 uppercase tracking-wider px-1">
                            Suggested for this page
                        </p>
                        {suggestedPrompts.map((prompt, i) => (
                            <button
                                key={i}
                                onClick={() => onSendPrompt(prompt)}
                                disabled={isAsking}
                                className="w-full text-left px-3 py-2.5 rounded-xl border border-gray-200 dark:border-gray-700 text-xs text-gray-700 dark:text-gray-300 hover:bg-violet-50 dark:hover:bg-violet-900/20 hover:border-violet-300 dark:hover:border-violet-700 transition-colors disabled:opacity-50"
                            >
                                "{prompt}"
                            </button>
                        ))}
                    </div>
                )}
            </div>
        );
    }

    return (
        <div className="p-3 space-y-3">
            {/* Clear button */}
            <div className="flex justify-end">
                <button
                    onClick={onClear}
                    className="flex items-center gap-1 text-[10px] text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
                >
                    <Trash2 className="h-3 w-3" />
                    Clear chat
                </button>
            </div>

            {/* Messages */}
            {messages.map((msg, i) => (
                <div
                    key={i}
                    className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
                >
                    <div
                        className={`max-w-[85%] rounded-2xl px-3.5 py-2.5 text-sm leading-relaxed ${msg.role === 'user'
                                ? 'bg-violet-600 text-white rounded-br-md'
                                : 'bg-gray-100 dark:bg-gray-800 text-gray-900 dark:text-gray-100 rounded-bl-md'
                            }`}
                    >
                        {msg.role === 'assistant' ? (
                            <div className="whitespace-pre-wrap break-words">
                                {msg.content}
                                {msg.toolCalls != null && msg.toolCalls > 0 && (
                                    <p className="mt-1.5 text-[10px] text-gray-400 dark:text-gray-500 italic">
                                        📊 Queried {msg.toolCalls} data source{msg.toolCalls !== 1 ? 's' : ''}
                                    </p>
                                )}
                            </div>
                        ) : (
                            <span className="whitespace-pre-wrap break-words">{msg.content}</span>
                        )}
                    </div>
                </div>
            ))}

            {/* Typing indicator */}
            {isAsking && (
                <div className="flex justify-start">
                    <div className="bg-gray-100 dark:bg-gray-800 rounded-2xl rounded-bl-md px-4 py-3">
                        <div className="flex gap-1">
                            <span className="h-2 w-2 rounded-full bg-gray-400 animate-bounce" style={{ animationDelay: '0ms' }} />
                            <span className="h-2 w-2 rounded-full bg-gray-400 animate-bounce" style={{ animationDelay: '150ms' }} />
                            <span className="h-2 w-2 rounded-full bg-gray-400 animate-bounce" style={{ animationDelay: '300ms' }} />
                        </div>
                    </div>
                </div>
            )}

            <div ref={messagesEndRef} />
        </div>
    );
}


// ── Anomalies Tab ────────────────────────────────────────────────

function AnomaliesTab({
    anomalies, onDismiss, onRefresh, isRefreshing,
}: {
    anomalies: AiCachedResult[];
    onDismiss: (id: number) => void;
    onRefresh: () => void;
    isRefreshing: boolean;
}) {
    return (
        <div className="p-3 space-y-3">
            {/* Header row */}
            <div className="flex items-center justify-between">
                <p className="text-xs font-medium text-gray-500 dark:text-gray-400">
                    {anomalies.length} active anomal{anomalies.length !== 1 ? 'ies' : 'y'}
                </p>
                <button
                    onClick={onRefresh}
                    disabled={isRefreshing}
                    className="flex items-center gap-1 text-xs text-violet-600 dark:text-violet-400 hover:text-violet-800 dark:hover:text-violet-300 disabled:opacity-50 transition-colors"
                >
                    <RefreshCw className={`h-3 w-3 ${isRefreshing ? 'animate-spin' : ''}`} />
                    {isRefreshing ? 'Scanning…' : 'Scan Now'}
                </button>
            </div>

            {anomalies.length === 0 && !isRefreshing && (
                <EmptyNotice
                    icon={<AlertTriangle className="h-5 w-5 text-green-500" />}
                    title="No anomalies detected"
                    subtitle="AI scans your data nightly at 4 AM. Everything looks good."
                />
            )}

            {isRefreshing && anomalies.length === 0 && (
                <div className="flex flex-col items-center py-8 gap-2">
                    <Loader2 className="h-6 w-6 animate-spin text-violet-500" />
                    <p className="text-xs text-gray-500">Analyzing your data…</p>
                </div>
            )}

            {anomalies.map((a) => (
                <div
                    key={a.id}
                    className={`rounded-xl border p-3 space-y-1.5 ${severityColor(a.severity)}`}
                >
                    <div className="flex items-start justify-between gap-2">
                        <div className="flex items-center gap-2 min-w-0">
                            <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium ${severityBadge(a.severity)}`}>
                                {a.severity ?? 'info'}
                            </span>
                            <span className="text-xs font-medium text-gray-900 dark:text-gray-100 truncate">
                                {a.title}
                            </span>
                        </div>
                        <button
                            onClick={() => onDismiss(a.id)}
                            className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 flex-shrink-0 p-0.5"
                            title="Dismiss"
                        >
                            <X className="h-3.5 w-3.5" />
                        </button>
                    </div>
                    <p className="text-xs text-gray-600 dark:text-gray-300 leading-relaxed">
                        {a.body}
                    </p>
                    <p className="text-[10px] text-gray-400 dark:text-gray-500">
                        {a.category} · {new Date(a.created_at).toLocaleDateString()}
                    </p>
                </div>
            ))}
        </div>
    );
}


// ── Predictions Tab ──────────────────────────────────────────────

function PredictionsTab({
    predictions, onRefresh, isRefreshing,
}: {
    predictions: AiCachedResult[];
    onRefresh: () => void;
    isRefreshing: boolean;
}) {
    return (
        <div className="p-3 space-y-3">
            {/* Header row */}
            <div className="flex items-center justify-between">
                <p className="text-xs font-medium text-gray-500 dark:text-gray-400">
                    {predictions.length} prediction{predictions.length !== 1 ? 's' : ''}
                </p>
                <button
                    onClick={onRefresh}
                    disabled={isRefreshing}
                    className="flex items-center gap-1 text-xs text-violet-600 dark:text-violet-400 hover:text-violet-800 dark:hover:text-violet-300 disabled:opacity-50 transition-colors"
                >
                    <RefreshCw className={`h-3 w-3 ${isRefreshing ? 'animate-spin' : ''}`} />
                    {isRefreshing ? 'Generating…' : 'Refresh'}
                </button>
            </div>

            {predictions.length === 0 && !isRefreshing && (
                <EmptyNotice
                    icon={<ShoppingCart className="h-5 w-5 text-violet-500" />}
                    title="No predictions yet"
                    subtitle="AI generates ordering suggestions nightly at 4:30 AM based on 90-day usage patterns."
                />
            )}

            {isRefreshing && predictions.length === 0 && (
                <div className="flex flex-col items-center py-8 gap-2">
                    <Loader2 className="h-6 w-6 animate-spin text-violet-500" />
                    <p className="text-xs text-gray-500">Analyzing usage patterns…</p>
                </div>
            )}

            {predictions.map((p) => (
                <div
                    key={p.id}
                    className="rounded-xl border border-violet-200 bg-violet-50 dark:border-violet-700 dark:bg-violet-900/20 p-3 space-y-1.5"
                >
                    <div className="flex items-center gap-2">
                        <ChevronDown className="h-3.5 w-3.5 text-violet-500 flex-shrink-0" />
                        <span className="text-xs font-medium text-gray-900 dark:text-gray-100">
                            {p.title}
                        </span>
                    </div>
                    <p className="text-xs text-gray-600 dark:text-gray-300 leading-relaxed pl-5">
                        {p.body}
                    </p>
                    <p className="text-[10px] text-gray-400 dark:text-gray-500 pl-5">
                        {p.category} · {new Date(p.created_at).toLocaleDateString()}
                    </p>
                </div>
            ))}
        </div>
    );
}


// ── Shared empty state ──────────────────────────────────────────

function EmptyNotice({
    icon, title, subtitle,
}: {
    icon: React.ReactNode;
    title: string;
    subtitle: string;
}) {
    return (
        <div className="text-center py-8 space-y-2">
            <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 dark:bg-gray-800">
                {icon}
            </div>
            <p className="text-xs font-medium text-gray-700 dark:text-gray-300">{title}</p>
            <p className="text-[10px] text-gray-400 dark:text-gray-500 max-w-[260px] mx-auto">{subtitle}</p>
        </div>
    );
}


// ── Disabled feature placeholder ────────────────────────────────

function DisabledFeature({ feature }: { feature: string }) {
    return (
        <div className="text-center py-12 px-4 space-y-2">
            <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 dark:bg-gray-800">
                <Bot className="h-5 w-5 text-gray-400" />
            </div>
            <p className="text-xs font-medium text-gray-700 dark:text-gray-300">
                {feature} is disabled
            </p>
            <p className="text-[10px] text-gray-400 dark:text-gray-500 max-w-[240px] mx-auto">
                Enable this feature in Settings → AI Config to start using it.
            </p>
        </div>
    );
}
