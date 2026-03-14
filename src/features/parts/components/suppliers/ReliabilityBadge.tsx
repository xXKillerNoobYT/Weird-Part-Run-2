/**
 * ReliabilityBadge — small colored metric display for supplier reliability scores.
 */


interface ReliabilityBadgeProps {
  label: string;
  value: number;
  format: 'percent' | 'days';
}

export function ReliabilityBadge({ label, value, format }: ReliabilityBadgeProps) {
  let display: string;
  let color: string;

  if (format === 'percent') {
    const pct = Math.round(value * 100);
    display = `${pct}%`;
    color = pct >= 90 ? 'text-green-600 dark:text-green-400'
      : pct >= 75 ? 'text-amber-600 dark:text-amber-400'
        : 'text-red-600 dark:text-red-400';
  } else {
    display = `${value}d`;
    color = value <= 3 ? 'text-green-600 dark:text-green-400'
      : value <= 7 ? 'text-amber-600 dark:text-amber-400'
        : 'text-red-600 dark:text-red-400';
  }

  return (
    <div className="flex items-center gap-1">
      <span className="text-gray-500 dark:text-gray-400">{label}:</span>
      <span className={`font-semibold ${color}`}>{display}</span>
    </div>
  );
}
