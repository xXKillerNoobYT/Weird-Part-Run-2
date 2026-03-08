/**
 * PartIdentity — Reusable component for displaying part identification.
 *
 * Shows part name/description, code chip, brand badge, color chip,
 * and category/type breadcrumb. Two modes:
 *   - Default (multi-line): for cards, detail views, larger contexts
 *   - Compact (single-line): for table cells, checklists, inline usage
 *
 * Handles all nullable fields gracefully — renders nothing for missing data.
 */

import { cn } from '../../lib/utils';

export interface PartIdentityProps {
    /** Primary display name (bold). Falls back to partDescription, then "Part #partId". */
    partName?: string | null;
    /** Secondary description — used as fallback if no partName */
    partDescription?: string | null;
    /** Part code (gray monospace chip) */
    partNumber?: string | null;
    /** Ultimate fallback: "Part #4" */
    partId?: number;
    /** Category name (gray breadcrumb text) */
    categoryName?: string | null;
    /** Type name (gray breadcrumb text, shown after category) */
    typeName?: string | null;
    /** Color name (purple chip) */
    colorName?: string | null;
    /** Color hex code (dot swatch next to color name) */
    colorHex?: string | null;
    /** Brand name (blue chip) */
    brandName?: string | null;
    /** Single-line mode for table cells and checklists */
    compact?: boolean;
    /** Container className override */
    className?: string;
}

export function PartIdentity({
    partName,
    partDescription,
    partNumber,
    partId,
    categoryName,
    typeName,
    colorName,
    colorHex,
    brandName,
    compact = false,
    className,
}: PartIdentityProps) {
    // Resolve the primary display text
    const displayName = partName || partDescription || (partId ? `Part #${partId}` : 'Unknown Part');

    // Build the category/type breadcrumb
    const breadcrumb = [categoryName, typeName].filter(Boolean).join(' › ');

    if (compact) {
        return (
            <div className={cn('flex items-center gap-1.5 min-w-0', className)}>
                <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                    {displayName}
                </span>
                {partNumber && (
                    <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1 py-0.5 rounded shrink-0">
                        {partNumber}
                    </span>
                )}
                {brandName && (
                    <span className="text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 px-1.5 py-0.5 rounded shrink-0">
                        {brandName}
                    </span>
                )}
                {colorName && (
                    <span className="text-xs bg-purple-100 dark:bg-purple-900/30 text-purple-700 dark:text-purple-300 px-1.5 py-0.5 rounded shrink-0 inline-flex items-center gap-1">
                        {colorHex && (
                            <span
                                className="inline-block w-2 h-2 rounded-full border border-gray-300 dark:border-gray-600"
                                style={{ backgroundColor: colorHex }}
                            />
                        )}
                        {colorName}
                    </span>
                )}
                {breadcrumb && (
                    <span className="text-xs text-gray-500 dark:text-gray-400 truncate shrink">
                        {breadcrumb}
                    </span>
                )}
            </div>
        );
    }

    // Default mode (multi-line)
    return (
        <div className={cn('min-w-0', className)}>
            <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                {displayName}
            </p>
            <div className="flex items-center gap-1.5 flex-wrap mt-0.5">
                {partNumber && (
                    <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1 py-0.5 rounded">
                        {partNumber}
                    </span>
                )}
                {brandName && (
                    <span className="text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 px-1.5 py-0.5 rounded">
                        {brandName}
                    </span>
                )}
                {colorName && (
                    <span className="text-xs bg-purple-100 dark:bg-purple-900/30 text-purple-700 dark:text-purple-300 px-1.5 py-0.5 rounded inline-flex items-center gap-1">
                        {colorHex && (
                            <span
                                className="inline-block w-2 h-2 rounded-full border border-gray-300 dark:border-gray-600"
                                style={{ backgroundColor: colorHex }}
                            />
                        )}
                        {colorName}
                    </span>
                )}
                {breadcrumb && (
                    <span className="text-xs text-gray-500 dark:text-gray-400">
                        {breadcrumb}
                    </span>
                )}
            </div>
        </div>
    );
}
