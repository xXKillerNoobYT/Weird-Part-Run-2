/**
 * Foundation Models Service — TypeScript interface to on-device AI.
 *
 * Cross-platform:
 *   - macOS/iOS: Apple Foundation Models (Swift FFI via Tauri IPC)
 *   - Windows: llama.cpp sidecar (OpenAI-compatible local API)
 *   - Web browser: no-op (returns 'not_native')
 *
 * Architecture:
 *   1. Check availability → cached after first call
 *   2. Submit request (async, non-blocking)
 *   3. Poll for result until complete
 *   4. Return text or error
 */

import { isTauri } from './environment';

// ── Types ──────────────────────────────────────────────────────────

export type LlmAvailability =
  | 'available'
  // Apple-specific
  | 'not_eligible'
  | 'not_enabled'
  | 'not_ready'
  // Windows-specific
  | 'not_installed' // llama-server + model both missing
  | 'no_server'     // llama-server.exe missing
  | 'no_model'      // no .gguf model file found
  // Generic
  | 'unavailable'
  | 'not_native';

export interface LlmResult {
  success: boolean;
  text: string | null;
  error: string | null;
}

export type EnhanceMode = 'proofread' | 'rewrite' | 'summarize' | 'expand' | 'professional';

export interface CompletionOptions {
  /** Maximum characters of context to send (to manage the 4096 token window) */
  maxContextChars?: number;
  /** Field context: what type of data this field holds */
  fieldType?: string;
  /** Additional context data (job name, part info, etc.) */
  contextData?: Record<string, string>;
}

// ── Tauri Invoke Helper ────────────────────────────────────────────

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke: tauriInvoke } = await import('@tauri-apps/api/core');
  return tauriInvoke<T>(cmd, args);
}

// ── Availability ───────────────────────────────────────────────────

let cachedAvailability: LlmAvailability | null = null;

/**
 * Check if on-device AI is available.
 * - macOS/iOS: Apple Foundation Models
 * - Windows: llama.cpp sidecar
 * Result is cached after first call. Use resetAvailability() to re-check.
 */
export async function checkAvailability(): Promise<LlmAvailability> {
  if (cachedAvailability) return cachedAvailability;

  if (!isTauri()) {
    cachedAvailability = 'not_native';
    return cachedAvailability;
  }

  try {
    const status = await invoke<string>('llm_check_availability');
    cachedAvailability = status as LlmAvailability;
  } catch {
    cachedAvailability = 'unavailable';
  }

  return cachedAvailability;
}

/** Whether on-device AI is ready to use right now. */
export async function isAvailable(): Promise<boolean> {
  return (await checkAvailability()) === 'available';
}

/** Reset cached availability — call after user changes AI settings or installs a model. */
export async function resetAvailability(): Promise<void> {
  cachedAvailability = null;
  if (isTauri()) {
    try {
      await invoke('llm_reset_availability');
    } catch {
      // Ignore — non-critical
    }
  }
}

// ── Request / Poll Loop ────────────────────────────────────────────

let requestCounter = 0;

function generateRequestId(): string {
  return `req-${Date.now()}-${++requestCounter}`;
}

/**
 * Submit a generation request and poll until it completes.
 *
 * @param prompt - The text prompt to send to the model
 * @param instructions - System instructions for the model session
 * @param timeoutMs - Maximum time to wait (default 15 seconds)
 * @returns The generated text, or throws on error
 */
async function generateRaw(
  prompt: string,
  instructions: string,
  timeoutMs = 15_000,
): Promise<string> {
  if (!(await isAvailable())) {
    throw new Error('On-device AI is not available. Check Settings → AI to configure.');
  }

  const requestId = generateRequestId();

  // Submit the request
  await invoke<boolean>('llm_request', {
    requestId,
    prompt,
    instructions,
    toolsJson: null,
  });

  // Poll for result
  const startTime = Date.now();
  const pollInterval = 200; // ms

  return new Promise<string>((resolve, reject) => {
    const poll = async () => {
      if (Date.now() - startTime > timeoutMs) {
        // Cancel the request on timeout
        try {
          await invoke('llm_cancel_request', { requestId });
        } catch {
          // ignore
        }
        reject(new Error('AI generation timed out. The model may be busy.'));
        return;
      }

      try {
        const result = await invoke<LlmResult | null>('llm_poll_result', { requestId });

        if (result === null) {
          // Not ready yet — poll again
          setTimeout(poll, pollInterval);
          return;
        }

        if (result.success && result.text) {
          resolve(result.text);
        } else {
          reject(new Error(result.error ?? 'AI generation failed.'));
        }
      } catch (err) {
        reject(err);
      }
    };

    // Start polling
    setTimeout(poll, pollInterval);
  });
}

// ── Public API ─────────────────────────────────────────────────────

/**
 * Generate a text completion for the given partial text.
 *
 * @param partialText - What the user has typed so far
 * @param options - Context and field type information
 * @returns The suggested completion text (NOT the full text — just the continuation)
 */
export async function generateCompletion(
  partialText: string,
  options: CompletionOptions = {},
): Promise<string> {
  if (!partialText.trim()) return '';

  const maxChars = options.maxContextChars ?? 1000;
  const truncatedText = partialText.slice(-maxChars);

  let contextStr = '';
  if (options.contextData) {
    const entries = Object.entries(options.contextData)
      .map(([k, v]) => `${k}: ${v}`)
      .join('\n');
    contextStr = `\nContext:\n${entries}\n`;
  }

  const instructions = [
    'You are a helpful assistant for an electrical contracting business.',
    'Complete the user\'s text naturally. Only provide the continuation — do NOT repeat what they already wrote.',
    'Keep completions concise (1-2 sentences max).',
    'Use professional trade language appropriate for electrical work.',
    options.fieldType ? `This is a "${options.fieldType}" field.` : '',
    contextStr,
  ]
    .filter(Boolean)
    .join(' ');

  const prompt = `Complete this text:\n"${truncatedText}"`;

  return generateRaw(prompt, instructions);
}

/**
 * Enhance existing text (proofread, rewrite, summarize, expand, or make professional).
 *
 * @param text - The full text to enhance
 * @param mode - The type of enhancement
 * @returns The enhanced text (full replacement, not a diff)
 */
export async function enhanceText(text: string, mode: EnhanceMode): Promise<string> {
  if (!text.trim()) return text;

  const modeInstructions: Record<EnhanceMode, string> = {
    proofread:
      'Fix any grammar, spelling, and punctuation errors in the text. Keep the original meaning and style. Return only the corrected text.',
    rewrite:
      'Rewrite the text to improve clarity and readability while keeping the same meaning. Use professional trade language. Return only the rewritten text.',
    summarize:
      'Summarize the text concisely, keeping the key information. Return only the summary.',
    expand:
      'Expand on the text by adding relevant detail and explanation while keeping the same tone. Return only the expanded text.',
    professional:
      'Rewrite the text in a professional business tone suitable for client-facing communication. Return only the rewritten text.',
  };

  const instructions = [
    'You are a helpful assistant for an electrical contracting business.',
    modeInstructions[mode],
  ].join(' ');

  return generateRaw(text, instructions);
}

/**
 * Generate a pre-fill draft for a new empty field based on context.
 *
 * @param fieldType - What kind of content this field expects
 * @param contextData - Relevant data to build the draft from
 * @returns A suggested draft, or empty string if nothing useful can be generated
 */
export async function generatePreFill(
  fieldType: string,
  contextData: Record<string, string>,
): Promise<string> {
  if (Object.keys(contextData).length === 0) return '';

  const contextStr = Object.entries(contextData)
    .map(([k, v]) => `${k}: ${v}`)
    .join('\n');

  const instructions = [
    'You are a helpful assistant for an electrical contracting business.',
    `Generate a brief, professional draft for a "${fieldType}" field based on the provided context.`,
    'Keep it concise and relevant. Use trade-appropriate language.',
    'Return only the draft text, nothing else.',
  ].join(' ');

  const prompt = `Context:\n${contextStr}\n\nWrite a draft for the ${fieldType} field.`;

  try {
    return await generateRaw(prompt, instructions, 10_000);
  } catch {
    return ''; // Silent failure — pre-fill is optional
  }
}

// ── Windows-specific Helpers ───────────────────────────────────────

/**
 * Get the directory where GGUF model files should be placed (Windows only).
 * Returns empty string on non-Windows platforms.
 */
export async function getModelsDir(): Promise<string> {
  if (!isTauri()) return '';
  try {
    return await invoke<string>('llm_get_models_dir');
  } catch {
    return '';
  }
}

/**
 * Get the directory where llama-server.exe should be placed (Windows only).
 * Returns empty string on non-Windows platforms.
 */
export async function getServerDir(): Promise<string> {
  if (!isTauri()) return '';
  try {
    return await invoke<string>('llm_get_server_dir');
  } catch {
    return '';
  }
}

/**
 * Gracefully shut down the llama.cpp sidecar process (Windows only).
 * Normally called automatically when the app closes.
 */
export async function shutdownLlm(): Promise<void> {
  if (!isTauri()) return;
  try {
    await invoke('llm_shutdown');
  } catch {
    // Ignore — best-effort cleanup
  }
}

/**
 * Get a human-readable description of the current availability status.
 * Useful for displaying in the UI.
 */
export function getAvailabilityMessage(status: LlmAvailability): string {
  switch (status) {
    case 'available':
      return 'On-device AI is ready';
    case 'not_eligible':
      return 'This device does not support Apple Intelligence';
    case 'not_enabled':
      return 'Apple Intelligence is not enabled in System Settings';
    case 'not_ready':
      return 'AI model is loading…';
    case 'not_installed':
      return 'llama-server and AI model not found — see setup instructions';
    case 'no_server':
      return 'llama-server.exe not found — download from llama.cpp releases';
    case 'no_model':
      return 'No GGUF model file found — download a model to the models folder';
    case 'unavailable':
      return 'On-device AI is not available';
    case 'not_native':
      return 'On-device AI requires the desktop app';
    default:
      return 'Unknown AI status';
  }
}
