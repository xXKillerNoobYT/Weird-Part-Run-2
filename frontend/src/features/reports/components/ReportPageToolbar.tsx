/**
 * ReportPageToolbar — shared toolbar for all report pages.
 *
 * Adds Print, Share, and Template Save buttons in a compact row.
 * Drop into any report page's header area.
 */

import { useState } from 'react';
import { Printer, Share2 } from 'lucide-react';
import ReportTemplateBar from './ReportTemplateBar';
import ShareReportModal from './ShareReportModal';


interface Props {
  reportType: string;
  /** Current filter config to save/share */
  currentConfig: Record<string, unknown>;
  /** Called when a saved template is loaded */
  onLoadTemplate: (config: Record<string, unknown>) => void;
  /** Context params for share links */
  shareContextParams?: Record<string, unknown>;
  /** Optional label for generated share links */
  shareLabel?: string;
  /** Hide the Print button (use when page already has its own) */
  hidePrint?: boolean;
}

export default function ReportPageToolbar({
  reportType,
  currentConfig,
  onLoadTemplate,
  shareContextParams,
  shareLabel,
  hidePrint = false,
}: Props) {
  const [shareOpen, setShareOpen] = useState(false);

  return (
    <>
      <div className="flex flex-wrap items-center gap-2 no-print">
        {/* Print (optional — hide when page provides its own) */}
        {!hidePrint && (
          <button
            onClick={() => window.print()}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg
                       border border-gray-300 dark:border-gray-600
                       text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700
                       min-h-[44px]"
            title="Print this report"
          >
            <Printer className="h-4 w-4" />
            <span className="hidden sm:inline">Print</span>
          </button>
        )}

        {/* Share */}
        <button
          onClick={() => setShareOpen(true)}
          className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg
                     border border-gray-300 dark:border-gray-600
                     text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700
                     min-h-[44px]"
          title="Share report via link"
        >
          <Share2 className="h-4 w-4" />
          <span className="hidden sm:inline">Share</span>
        </button>

        {/* Template Bar */}
        <ReportTemplateBar
          reportType={reportType}
          currentConfig={currentConfig}
          onLoadTemplate={onLoadTemplate}
        />
      </div>

      {/* Share Modal */}
      <ShareReportModal
        isOpen={shareOpen}
        onClose={() => setShareOpen(false)}
        reportType={reportType}
        contextParams={shareContextParams || currentConfig}
        defaultLabel={shareLabel}
      />
    </>
  );
}
