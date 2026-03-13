/**
 * ErrorFallback — reusable error display for failed queries and render crashes.
 *
 * Use for:
 *   1. Query error states: `if (isError) return <ErrorFallback onRetry={refetch} />`
 *   2. ErrorBoundary fallback: `<ErrorBoundary FallbackComponent={ErrorFallback}>`
 *   3. Inline section errors: `<ErrorFallback compact message="..." />`
 */

import { AlertTriangle, RefreshCw } from 'lucide-react';
import { Button } from './Button';

interface ErrorFallbackProps {
    /** Primary message shown to the user */
    message?: string;
    /** Smaller descriptive text below the title */
    description?: string;
    /** Called when user clicks "Try Again" */
    onRetry?: () => void;
    /** Compact inline variant (no full-page centering) */
    compact?: boolean;
    /** Optional error object for context */
    error?: Error | null;
}

export function ErrorFallback({
    message = 'Something went wrong',
    description = 'Please try again or refresh the page.',
    onRetry,
    compact = false,
    error,
}: ErrorFallbackProps) {
    if (compact) {
        return (
            <div className="flex items-center gap-3 p-4 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
                <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-red-700 dark:text-red-300">{message}</p>
                    {error?.message && (
                        <p className="text-xs text-red-500 dark:text-red-400 mt-0.5 truncate">{error.message}</p>
                    )}
                </div>
                {onRetry && (
                    <Button variant="ghost" size="sm" icon={<RefreshCw size={14} />} onClick={onRetry}>
                        Retry
                    </Button>
                )}
            </div>
        );
    }

    return (
        <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-red-100 dark:bg-red-900/30 mb-4">
                <AlertTriangle className="h-7 w-7 text-red-500" />
            </div>
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1">
                {message}
            </h2>
            <p className="text-sm text-gray-500 dark:text-gray-400 max-w-sm mb-4">
                {description}
            </p>
            {error?.message && (
                <p className="text-xs text-red-500 dark:text-red-400 mb-4 max-w-md truncate">
                    {error.message}
                </p>
            )}
            {onRetry && (
                <Button variant="primary" size="sm" icon={<RefreshCw size={16} />} onClick={onRetry}>
                    Try Again
                </Button>
            )}
        </div>
    );
}
