/**
 * AiSuggestionPopover — floating popover for AI text enhancement options.
 *
 * Shows proofread, rewrite, summarize, expand, and professional tone options.
 * Displays a before/after preview when a result is ready.
 */

import { useState, useRef, useEffect } from 'react';
import { Loader2, Check, X } from 'lucide-react';
import type { EnhanceMode } from '../../lib/foundation-models';

interface AiSuggestionPopoverProps {
  open: boolean;
  onClose: () => void;
  onEnhance: (mode: EnhanceMode) => Promise<string>;
  onAcceptEnhancement: (text: string) => void;
  currentText: string;
}

const MODES: { mode: EnhanceMode; label: string; description: string }[] = [
  { mode: 'proofread', label: 'Proofread', description: 'Fix grammar & spelling' },
  { mode: 'rewrite', label: 'Rewrite', description: 'Improve clarity' },
  { mode: 'summarize', label: 'Summarize', description: 'Condense the text' },
  { mode: 'expand', label: 'Expand', description: 'Add more detail' },
  { mode: 'professional', label: 'Professional', description: 'Business tone' },
];

export function AiSuggestionPopover({
  open,
  onClose,
  onEnhance,
  onAcceptEnhancement,
  currentText,
}: AiSuggestionPopoverProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [enhancedText, setEnhancedText] = useState<string | null>(null);
  const [selectedMode, setSelectedMode] = useState<EnhanceMode | null>(null);
  const popoverRef = useRef<HTMLDivElement>(null);

  // Close on click outside
  useEffect(() => {
    if (!open) return;

    const handleClickOutside = (e: MouseEvent) => {
      if (popoverRef.current && !popoverRef.current.contains(e.target as Node)) {
        handleClose();
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [open]);

  // Close on Escape
  useEffect(() => {
    if (!open) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleClose();
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [open]);

  const handleClose = () => {
    setEnhancedText(null);
    setSelectedMode(null);
    setIsLoading(false);
    onClose();
  };

  const handleEnhance = async (mode: EnhanceMode) => {
    if (!currentText.trim()) return;

    setSelectedMode(mode);
    setIsLoading(true);
    setEnhancedText(null);

    try {
      const result = await onEnhance(mode);
      setEnhancedText(result);
    } catch {
      setEnhancedText(null);
    } finally {
      setIsLoading(false);
    }
  };

  const handleAccept = () => {
    if (enhancedText) {
      onAcceptEnhancement(enhancedText);
    }
    handleClose();
  };

  if (!open) return null;

  return (
    <div
      ref={popoverRef}
      className="absolute bottom-full mb-1 right-0 z-50 w-72 rounded-xl border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-gray-900"
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-gray-100 dark:border-gray-800">
        <span className="text-xs font-semibold text-gray-700 dark:text-gray-300">
          Enhance Text
        </span>
        <button
          onClick={handleClose}
          className="p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
        >
          <X className="h-3.5 w-3.5 text-gray-400" />
        </button>
      </div>

      {/* Mode buttons (when no result yet) */}
      {!enhancedText && !isLoading && (
        <div className="p-2 space-y-0.5">
          {MODES.map(({ mode, label, description }) => (
            <button
              key={mode}
              onClick={() => handleEnhance(mode)}
              disabled={!currentText.trim()}
              className="w-full flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-left hover:bg-violet-50 dark:hover:bg-violet-900/20 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <div>
                <span className="text-xs font-medium text-gray-800 dark:text-gray-200">
                  {label}
                </span>
                <span className="text-[10px] text-gray-400 dark:text-gray-500 ml-1.5">
                  {description}
                </span>
              </div>
            </button>
          ))}
        </div>
      )}

      {/* Loading state */}
      {isLoading && (
        <div className="flex flex-col items-center gap-2 py-6">
          <Loader2 className="h-5 w-5 animate-spin text-violet-500" />
          <span className="text-xs text-gray-500">
            {selectedMode === 'proofread' ? 'Proofreading…' : `${selectedMode ? selectedMode.charAt(0).toUpperCase() + selectedMode.slice(1) : 'Enhancing'}…`}
          </span>
        </div>
      )}

      {/* Result preview */}
      {enhancedText && !isLoading && (
        <div className="p-3 space-y-2">
          <p className="text-[10px] font-medium text-gray-400 dark:text-gray-500 uppercase tracking-wider">
            {selectedMode} result
          </p>
          <div className="max-h-32 overflow-y-auto rounded-lg bg-gray-50 dark:bg-gray-800/50 p-2.5 text-xs text-gray-700 dark:text-gray-300 leading-relaxed">
            {enhancedText}
          </div>
          <div className="flex gap-2">
            <button
              onClick={handleAccept}
              className="flex-1 flex items-center justify-center gap-1.5 py-2 rounded-lg bg-violet-600 text-white text-xs font-medium hover:bg-violet-700 transition-colors"
            >
              <Check className="h-3.5 w-3.5" />
              Use this
            </button>
            <button
              onClick={() => {
                setEnhancedText(null);
                setSelectedMode(null);
              }}
              className="px-3 py-2 rounded-lg border border-gray-200 dark:border-gray-700 text-xs text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
            >
              Back
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
