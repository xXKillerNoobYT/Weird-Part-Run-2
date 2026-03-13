/**
 * AI API functions — local LLM assistant via LM Studio.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 * Endpoint prefix: /api/ai
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';


// ── Types ────────────────────────────────────────────────────────

export interface AiAskRequest {
    question: string;
    conversation_history?: { role: string; content: string }[];
    page_context?: string;
}

export interface AiAskResponse {
    answer: string;
    tool_calls_made: number;
    model: string;
}

export interface AiSummarizeRequest {
    report_type: string;
    data: Record<string, unknown>;
}

export interface AiSummarizeResponse {
    summary: string;
    model: string;
}

export interface AiConnectionStatus {
    status: 'connected' | 'unreachable' | 'error';
    url: string;
    models: string[];
    model_count: number;
    error?: string;
}

export interface AiCachedResult {
    id: number;
    category: string;
    title: string;
    body: string;
    severity?: 'info' | 'warning' | 'critical';
    context_json?: string;
    is_dismissed: number;
    created_at: string;
    expires_at?: string;
}

export interface AiPromptsResponse {
    page_context: string;
    prompts: string[];
}


// ── API Functions ────────────────────────────────────────────────

/** Check LM Studio connectivity and list available models. */
export async function getAiStatus(): Promise<AiConnectionStatus> {
    const { data } = await apiClient.get<ApiResponse<AiConnectionStatus>>(
        '/ai/status',
    );
    return data.data!;
}

/** Ask a natural language question with optional conversation context. */
export async function askAi(req: AiAskRequest): Promise<AiAskResponse> {
    const { data } = await apiClient.post<ApiResponse<AiAskResponse>>(
        '/ai/ask',
        req,
    );
    return data.data!;
}

/** Generate a natural language summary from report data. */
export async function summarizeReport(
    req: AiSummarizeRequest,
): Promise<AiSummarizeResponse> {
    const { data } = await apiClient.post<ApiResponse<AiSummarizeResponse>>(
        '/ai/summarize',
        req,
    );
    return data.data!;
}

/** Get cached anomaly detection results. */
export async function getAnomalies(
    includeDismissed = false,
): Promise<AiCachedResult[]> {
    const { data } = await apiClient.get<ApiResponse<AiCachedResult[]>>(
        '/ai/anomalies',
        { params: { include_dismissed: includeDismissed } },
    );
    return data.data ?? [];
}

/** Get cached ordering predictions. */
export async function getPredictions(): Promise<AiCachedResult[]> {
    const { data } = await apiClient.get<ApiResponse<AiCachedResult[]>>(
        '/ai/predictions',
    );
    return data.data ?? [];
}

/** Dismiss an anomaly by ID. */
export async function dismissAnomaly(resultId: number): Promise<void> {
    await apiClient.post('/ai/anomalies/dismiss', { result_id: resultId });
}

/** Force re-run anomaly detection and return fresh results. */
export async function refreshAnomalies(): Promise<AiCachedResult[]> {
    const { data } = await apiClient.post<ApiResponse<AiCachedResult[]>>(
        '/ai/anomalies/refresh',
    );
    return data.data ?? [];
}

/** Force re-run ordering predictions with configurable lookahead. */
export async function refreshPredictions(
    daysAhead = 30,
): Promise<AiCachedResult[]> {
    const { data } = await apiClient.post<ApiResponse<AiCachedResult[]>>(
        '/ai/predictions/refresh',
        null,
        { params: { days_ahead: daysAhead } },
    );
    return data.data ?? [];
}

/** Get context-aware suggested prompts for the current page. */
export async function getAiPrompts(
    pageContext: string,
): Promise<AiPromptsResponse> {
    const { data } = await apiClient.get<ApiResponse<AiPromptsResponse>>(
        '/ai/prompts',
        { params: { page_context: pageContext } },
    );
    return data.data!;
}

/** Get the count of active (non-dismissed) anomalies for badge display. */
export async function getAnomalyCount(): Promise<number> {
    const { data } = await apiClient.get<ApiResponse<{ count: number }>>(
        '/ai/anomaly-count',
    );
    return data.data?.count ?? 0;
}
