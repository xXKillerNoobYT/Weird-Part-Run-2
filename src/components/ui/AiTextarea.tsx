/**
 * AiTextarea — AI-enhanced textarea with inline autocomplete and text enhancement.
 *
 * Drop-in replacement for `<textarea>`. When Apple Intelligence is available,
 * adds:
 *   - Ghost text autocomplete (Tab to accept, Esc to dismiss)
 *   - Enhance button (proofread, rewrite, summarize, expand, professional)
 *   - Subtle AI indicator icon
 *
 * When AI is unavailable, renders a standard textarea with no extra UI.
 *
 * Usage:
 *   <AiTextarea
 *     value={notes}
 *     onChange={(e) => setNotes(e.target.value)}
 *     placeholder="Optional notes..."
 *     fieldId="job-notes"
 *     fieldType="job notes"
 *     contextData={{ jobName: 'Smith Residence', jobNumber: 'J-2024-042' }}
 *   />
 */

import { useRef, useCallback, useState, type TextareaHTMLAttributes } from 'react';
import { Sparkles, Loader2 } from 'lucide-react';
import { useAITextField, type AITextFieldOptions } from '../../hooks/useAITextField';
import { AiSuggestionPopover } from './AiSuggestionPopover';
import type { EnhanceMode } from '../../lib/foundation-models';

// ── Props ──────────────────────────────────────────────────────────

interface AiTextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  /** Unique ID for per-field AI preference storage */
  fieldId?: string;
  /** What kind of content this field holds (for AI context) */
  fieldType?: string;
  /** Additional context data for AI (job name, supplier, etc.) */
  contextData?: Record<string, string>;
  /** Enable inline autocomplete. Default: true */
  aiAutocomplete?: boolean;
  /** Enable enhance button. Default: true */
  aiEnhance?: boolean;
  /** Debounce before requesting completion. Default: 800ms */
  aiDebounceMs?: number;
}

// ── Component ──────────────────────────────────────────────────────

export function AiTextarea({
  fieldId,
  fieldType,
  contextData,
  aiAutocomplete = true,
  aiEnhance = true,
  aiDebounceMs = 800,
  value,
  onChange,
  className = '',
  ...textareaProps
}: AiTextareaProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [enhanceOpen, setEnhanceOpen] = useState(false);

  const aiOptions: AITextFieldOptions = {
    autocomplete: aiAutocomplete,
    enhance: aiEnhance,
    debounceMs: aiDebounceMs,
    fieldType,
    contextData,
    fieldId,
  };

  const ai = useAITextField(aiOptions);

  const currentValue = typeof value === 'string' ? value : '';

  // Handle text changes — forward to both parent and AI hook
  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      onChange?.(e);
      ai.onTextChange(e.target.value);
    },
    [onChange, ai.onTextChange],
  );

  // Handle keyboard shortcuts
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      // Tab to accept suggestion
      if (e.key === 'Tab' && ai.suggestion) {
        e.preventDefault();
        const completionText = ai.acceptSuggestion();
        // Create a synthetic change event with the appended text
        const newValue = currentValue + completionText;
        const textarea = textareaRef.current;
        if (textarea && onChange) {
          // Use native setter to trigger React's onChange properly
          const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
            window.HTMLTextAreaElement.prototype,
            'value',
          )?.set;
          nativeInputValueSetter?.call(textarea, newValue);
          const event = new Event('input', { bubbles: true });
          textarea.dispatchEvent(event);
        }
        return;
      }

      // Escape to dismiss suggestion
      if (e.key === 'Escape' && ai.suggestion) {
        e.preventDefault();
        ai.dismissSuggestion();
        return;
      }

      // Forward any existing onKeyDown
      textareaProps.onKeyDown?.(e);
    },
    [ai.suggestion, ai.acceptSuggestion, ai.dismissSuggestion, currentValue, onChange, textareaProps.onKeyDown],
  );

  // Handle enhance
  const handleEnhance = useCallback(
    async (mode: EnhanceMode): Promise<string> => {
      return ai.enhance(currentValue, mode);
    },
    [ai.enhance, currentValue],
  );

  // Accept enhanced text — replace the field content
  const handleAcceptEnhancement = useCallback(
    (text: string) => {
      const textarea = textareaRef.current;
      if (textarea && onChange) {
        const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
          window.HTMLTextAreaElement.prototype,
          'value',
        )?.set;
        nativeInputValueSetter?.call(textarea, text);
        const event = new Event('input', { bubbles: true });
        textarea.dispatchEvent(event);
      }
    },
    [onChange],
  );

  const showAiUi = ai.aiAvailable && !ai.aiDisabledForField;

  return (
    <div className="relative">
      {/* The actual textarea */}
      <textarea
        ref={textareaRef}
        value={value}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        className={className}
        {...textareaProps}
      />

      {/* Ghost text overlay (inline autocomplete) */}
      {showAiUi && ai.suggestion && (
        <div
          className="pointer-events-none absolute inset-0 overflow-hidden"
          aria-hidden="true"
        >
          {/*
            We render the current text as invisible + the suggestion as visible gray.
            This creates the "ghost text" effect after the cursor position.
          */}
          <div
            className="whitespace-pre-wrap break-words p-2.5 text-sm leading-relaxed"
            style={{
              // Match the textarea's padding/font exactly
              fontFamily: 'inherit',
              fontSize: 'inherit',
              lineHeight: 'inherit',
            }}
          >
            <span className="invisible">{currentValue}</span>
            <span className="text-gray-400 dark:text-gray-600">{ai.suggestion}</span>
          </div>
        </div>
      )}

      {/* AI indicator + enhance button */}
      {showAiUi && (
        <div className="absolute bottom-1.5 right-1.5 flex items-center gap-1">
          {/* Autocomplete hint */}
          {ai.suggestion && (
            <span className="text-[9px] text-gray-400 dark:text-gray-600 select-none">
              Tab to accept
            </span>
          )}

          {/* Loading spinner */}
          {(ai.isLoadingSuggestion || ai.isEnhancing) && (
            <Loader2 className="h-3.5 w-3.5 animate-spin text-violet-400" />
          )}

          {/* Enhance button */}
          {aiEnhance && currentValue.trim().length > 0 && !ai.isEnhancing && (
            <div className="relative">
              <button
                type="button"
                onClick={() => setEnhanceOpen(!enhanceOpen)}
                className="p-1 rounded-md hover:bg-violet-50 dark:hover:bg-violet-900/20 text-violet-400 hover:text-violet-600 dark:hover:text-violet-300 transition-colors"
                title="Enhance with AI"
              >
                <Sparkles className="h-3.5 w-3.5" />
              </button>

              <AiSuggestionPopover
                open={enhanceOpen}
                onClose={() => setEnhanceOpen(false)}
                onEnhance={handleEnhance}
                onAcceptEnhancement={handleAcceptEnhancement}
                currentText={currentValue}
              />
            </div>
          )}

          {/* AI available indicator (when no suggestion/loading) */}
          {!ai.suggestion && !ai.isLoadingSuggestion && !ai.isEnhancing && !currentValue.trim() && (
            <Sparkles className="h-3 w-3 text-gray-300 dark:text-gray-700" />
          )}
        </div>
      )}
    </div>
  );
}
