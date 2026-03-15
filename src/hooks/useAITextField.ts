/**
 * useAITextField — React hook for AI-enhanced text fields.
 *
 * Provides:
 *   - Inline autocomplete suggestions (ghost text)
 *   - Text enhancement (proofread, rewrite, summarize, expand, professional)
 *   - Context-aware pre-fill for new/empty fields
 *
 * The hook is a no-op when Apple Intelligence is unavailable.
 * All AI features degrade gracefully — the field always works normally.
 */

import { useState, useRef, useCallback, useEffect } from 'react';
import {
  checkAvailability,
  generateCompletion,
  enhanceText,
  generatePreFill,
  type LlmAvailability,
  type EnhanceMode,
  type CompletionOptions,
} from '../lib/foundation-models';

// ── Types ──────────────────────────────────────────────────────────

export interface AITextFieldOptions {
  /** Enable inline autocomplete suggestions. Default: true */
  autocomplete?: boolean;
  /** Enable the Enhance button. Default: true */
  enhance?: boolean;
  /** Debounce time in ms before requesting a completion. Default: 800 */
  debounceMs?: number;
  /** Context about what this field is for */
  fieldType?: string;
  /** Additional context data (e.g., job name, supplier, etc.) */
  contextData?: Record<string, string>;
  /** localStorage key to remember per-field AI opt-out */
  fieldId?: string;
}

export interface AITextFieldState {
  /** The current autocomplete suggestion (ghost text after cursor) */
  suggestion: string;
  /** Whether the model is currently generating a suggestion */
  isLoadingSuggestion: boolean;
  /** Whether the model is currently enhancing text */
  isEnhancing: boolean;
  /** Whether AI is available on this device */
  aiAvailable: boolean;
  /** Whether the user has disabled AI for this field */
  aiDisabledForField: boolean;
  /** Accept the current suggestion (append to value) */
  acceptSuggestion: () => string;
  /** Dismiss the current suggestion */
  dismissSuggestion: () => void;
  /** Enhance the given text with a specific mode */
  enhance: (text: string, mode: EnhanceMode) => Promise<string>;
  /** Generate a pre-fill draft for an empty field */
  getPreFill: () => Promise<string>;
  /** Toggle AI on/off for this specific field */
  toggleFieldAI: () => void;
  /** Call this when the text changes (for debounced autocomplete) */
  onTextChange: (text: string) => void;
}

// ── Per-field opt-out ──────────────────────────────────────────────

const AI_DISABLED_KEY = 'wiredpart_ai_disabled_fields';

function getDisabledFields(): Set<string> {
  try {
    const stored = localStorage.getItem(AI_DISABLED_KEY);
    return stored ? new Set(JSON.parse(stored)) : new Set();
  } catch {
    return new Set();
  }
}

function setDisabledFields(fields: Set<string>) {
  localStorage.setItem(AI_DISABLED_KEY, JSON.stringify([...fields]));
}

// ── Hook ───────────────────────────────────────────────────────────

export function useAITextField(options: AITextFieldOptions = {}): AITextFieldState {
  const {
    autocomplete = true,
    enhance: enableEnhance = true,
    debounceMs = 800,
    fieldType,
    contextData,
    fieldId,
  } = options;

  const [suggestion, setSuggestion] = useState('');
  const [isLoadingSuggestion, setIsLoadingSuggestion] = useState(false);
  const [isEnhancing, setIsEnhancing] = useState(false);
  const [aiAvailable, setAiAvailable] = useState(false);
  const [aiDisabledForField, setAiDisabledForField] = useState(false);

  const debounceTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const lastText = useRef('');
  const mounted = useRef(true);

  // Check availability on mount
  useEffect(() => {
    mounted.current = true;
    let cancelled = false;

    checkAvailability().then((status: LlmAvailability) => {
      if (!cancelled && mounted.current) {
        setAiAvailable(status === 'available');
      }
    });

    // Check per-field opt-out
    if (fieldId) {
      const disabled = getDisabledFields();
      setAiDisabledForField(disabled.has(fieldId));
    }

    return () => {
      mounted.current = false;
      cancelled = true;
      if (debounceTimer.current) clearTimeout(debounceTimer.current);
    };
  }, [fieldId]);

  const isActive = aiAvailable && !aiDisabledForField;

  // ── Autocomplete ──────────────────────────────────────────────

  const onTextChange = useCallback(
    (text: string) => {
      lastText.current = text;

      // Clear any pending suggestion request
      if (debounceTimer.current) clearTimeout(debounceTimer.current);

      // If autocomplete is disabled or no text, clear suggestion
      if (!isActive || !autocomplete || !text.trim() || text.length < 10) {
        setSuggestion('');
        return;
      }

      // Debounce the completion request
      debounceTimer.current = setTimeout(async () => {
        if (!mounted.current) return;
        setIsLoadingSuggestion(true);

        try {
          const completionOpts: CompletionOptions = { fieldType, contextData };
          const result = await generateCompletion(text, completionOpts);

          if (mounted.current && lastText.current === text) {
            setSuggestion(result);
          }
        } catch {
          // Silent failure — autocomplete is optional
          if (mounted.current) setSuggestion('');
        } finally {
          if (mounted.current) setIsLoadingSuggestion(false);
        }
      }, debounceMs);
    },
    [isActive, autocomplete, debounceMs, fieldType, contextData],
  );

  const acceptSuggestion = useCallback((): string => {
    const s = suggestion;
    setSuggestion('');
    return s;
  }, [suggestion]);

  const dismissSuggestion = useCallback(() => {
    setSuggestion('');
  }, []);

  // ── Enhance ───────────────────────────────────────────────────

  const handleEnhance = useCallback(
    async (text: string, mode: EnhanceMode): Promise<string> => {
      if (!isActive || !enableEnhance || !text.trim()) return text;

      setIsEnhancing(true);
      try {
        return await enhanceText(text, mode);
      } catch {
        return text; // Return original on failure
      } finally {
        if (mounted.current) setIsEnhancing(false);
      }
    },
    [isActive, enableEnhance],
  );

  // ── Pre-fill ──────────────────────────────────────────────────

  const getPreFill = useCallback(async (): Promise<string> => {
    if (!isActive || !contextData || Object.keys(contextData).length === 0) {
      return '';
    }

    return generatePreFill(fieldType ?? 'notes', contextData);
  }, [isActive, fieldType, contextData]);

  // ── Per-field toggle ──────────────────────────────────────────

  const toggleFieldAI = useCallback(() => {
    if (!fieldId) return;

    const disabled = getDisabledFields();
    if (disabled.has(fieldId)) {
      disabled.delete(fieldId);
      setAiDisabledForField(false);
    } else {
      disabled.add(fieldId);
      setAiDisabledForField(true);
    }
    setDisabledFields(disabled);
    setSuggestion('');
  }, [fieldId]);

  return {
    suggestion,
    isLoadingSuggestion,
    isEnhancing,
    aiAvailable,
    aiDisabledForField,
    acceptSuggestion,
    dismissSuggestion,
    enhance: handleEnhance,
    getPreFill,
    toggleFieldAI,
    onTextChange,
  };
}
