/**
 * AlternativeRow — displays a single linked alternative part.
 *
 * Shows: name, code, brand, relationship badge, preference star,
 * and edit/unlink controls (when not readOnly).
 */

import { Star, ArrowUpRight, ArrowLeftRight, Plug, Pencil, X } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import type { PartAlternative, AlternativeRelationship } from '../../../../lib/types';

interface AlternativeRowProps {
  alt: PartAlternative;
  /** The part_id we're viewing from — used to determine which "side" to display */
  viewingPartId: number;
  readOnly?: boolean;
  onEdit?: (alt: PartAlternative) => void;
  onUnlink?: (alt: PartAlternative) => void;
}

/** Map relationship type to icon + label + color */
const RELATIONSHIP_META: Record<AlternativeRelationship, {
  icon: React.ElementType;
  label: string;
  variant: 'default' | 'primary' | 'success' | 'warning' | 'danger';
}> = {
  substitute: {
    icon: ArrowLeftRight,
    label: 'Substitute',
    variant: 'default',
  },
  upgrade: {
    icon: ArrowUpRight,
    label: 'Upgrade',
    variant: 'primary',
  },
  compatible: {
    icon: Plug,
    label: 'Compatible',
    variant: 'success',
  },
};

export function AlternativeRow({
  alt,
  viewingPartId,
  readOnly = false,
  onEdit,
  onUnlink,
}: AlternativeRowProps) {
  // Bidirectional: determine which part is the "other" one
  const isViewingAsPrimary = alt.part_id === viewingPartId;
  const otherName = isViewingAsPrimary
    ? alt.alternative_name
    : alt.part_name;
  const otherCode = isViewingAsPrimary
    ? alt.alternative_code
    : alt.part_code;
  const brandName = alt.alternative_brand_name;

  const meta = RELATIONSHIP_META[alt.relationship as AlternativeRelationship]
    ?? RELATIONSHIP_META.substitute;
  const RelIcon = meta.icon;

  return (
    <div className="flex items-center gap-3 py-2.5 px-3 rounded-lg bg-gray-50 dark:bg-gray-800/50 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors group">
      {/* Preference star */}
      <div className="flex-shrink-0 w-5">
        {alt.preference > 0 ? (
          <Star className="h-4 w-4 text-amber-500 fill-amber-500" />
        ) : (
          <span className="h-4 w-4" />
        )}
      </div>

      {/* Part info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
            {otherName ?? 'Unknown Part'}
          </span>
          {otherCode && (
            <span className="text-xs text-gray-500 dark:text-gray-400 font-mono">
              {otherCode}
            </span>
          )}
        </div>
        {(brandName || alt.notes) && (
          <div className="flex items-center gap-2 mt-0.5">
            {brandName && (
              <span className="text-xs text-gray-500 dark:text-gray-400">
                {brandName}
              </span>
            )}
            {alt.notes && (
              <span className="text-xs text-gray-400 dark:text-gray-500 italic truncate">
                — {alt.notes}
              </span>
            )}
          </div>
        )}
      </div>

      {/* Relationship badge */}
      <Badge variant={meta.variant}>
        <RelIcon className="h-3 w-3 mr-1 inline" />
        {meta.label}
      </Badge>

      {/* Preference badge */}
      {alt.preference > 0 && (
        <Badge variant="warning">Preferred</Badge>
      )}

      {/* Action buttons (only in edit mode) */}
      {!readOnly && (
        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
          {onEdit && (
            <button
              className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
              onClick={() => onEdit(alt)}
              title="Edit link"
            >
              <Pencil className="h-3.5 w-3.5 text-gray-500 dark:text-gray-400" />
            </button>
          )}
          {onUnlink && (
            <button
              className="p-1 rounded hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
              onClick={() => onUnlink(alt)}
              title="Remove link"
            >
              <X className="h-3.5 w-3.5 text-red-400" />
            </button>
          )}
        </div>
      )}
    </div>
  );
}
