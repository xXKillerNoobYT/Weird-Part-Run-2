/**
 * BulkQRPrintModal — generate and print QR code labels for multiple parts at once.
 *
 * Opens a print-ready window with a grid of QR labels, each containing:
 * - QR code image (150×150px)
 * - Part name, code, category, brand, shelf, bin, unit
 *
 * Grid layout: 2 columns for standard label sheets (e.g., 2×4 per page).
 * Uses the client-side `qrcode` library — no server round-trip needed.
 */

import { useState, useEffect, useCallback } from 'react';
import QRCode from 'qrcode';
import { Printer, X, QrCode, Loader2 } from 'lucide-react';
import { Modal } from '../../../../components/ui/Modal';
import { Button } from '../../../../components/ui/Button';
import { Badge } from '../../../../components/ui/Badge';
import { encodeQRData } from '../../../../lib/qr-utils';
import type { WarehouseInventoryItem } from '../../../../lib/types';


interface BulkQRPrintModalProps {
    isOpen: boolean;
    onClose: () => void;
    items: WarehouseInventoryItem[];
}

interface QRLabelData {
    item: WarehouseInventoryItem;
    dataUri: string;
}


/** Build the bulk print page — grid of QR labels optimized for printing. */
function buildBulkPrintPage(printDoc: Document, labels: QRLabelData[]) {
    const style = printDoc.createElement('style');
    style.textContent = `
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      padding: 12px;
    }
    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    .label {
      border: 1px solid #ddd;
      border-radius: 6px;
      padding: 12px;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .label-inner { display: flex; gap: 12px; align-items: flex-start; }
    .qr-img { width: 120px; height: 120px; image-rendering: pixelated; flex-shrink: 0; }
    .details { flex: 1; min-width: 0; }
    .part-name { font-size: 13px; font-weight: 700; margin-bottom: 4px; word-wrap: break-word; }
    .detail-row { font-size: 10px; color: #555; padding: 1px 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .detail-label { font-weight: 600; color: #888; }
    .footer { text-align: center; font-size: 9px; color: #aaa; margin-top: 12px; }
    @media print {
      body { padding: 8px; }
      .label { border-color: #ccc; }
      .grid { gap: 8px; }
    }
  `;
    printDoc.head.appendChild(style);
    printDoc.title = `QR Labels — ${labels.length} parts`;

    const grid = printDoc.createElement('div');
    grid.className = 'grid';

    for (const { item, dataUri } of labels) {
        const label = printDoc.createElement('div');
        label.className = 'label';

        const inner = printDoc.createElement('div');
        inner.className = 'label-inner';

        // QR image
        const img = printDoc.createElement('img');
        img.src = dataUri;
        img.alt = 'QR';
        img.className = 'qr-img';
        inner.appendChild(img);

        // Details
        const details = printDoc.createElement('div');
        details.className = 'details';

        const nameEl = printDoc.createElement('div');
        nameEl.className = 'part-name';
        nameEl.textContent = item.part_name;
        details.appendChild(nameEl);

        const addRow = (label: string, value: string) => {
            const row = printDoc.createElement('div');
            row.className = 'detail-row';
            row.innerHTML = `<span class="detail-label">${label}:</span> ${value}`;
            details.appendChild(row);
        };

        if (item.part_code) addRow('Code', item.part_code);
        if (item.category_name) addRow('Category', item.category_name);
        if (item.brand_name) addRow('Brand', item.brand_name);
        if (item.shelf_location) addRow('Shelf', item.shelf_location);
        if (item.bin_location) addRow('Bin', item.bin_location);
        addRow('Unit', item.unit_of_measure);

        inner.appendChild(details);
        label.appendChild(inner);
        grid.appendChild(label);
    }

    printDoc.body.appendChild(grid);

    // Footer
    const footer = printDoc.createElement('div');
    footer.className = 'footer';
    footer.textContent = `Wired-Part Inventory Labels • ${labels.length} items • ${new Date().toLocaleDateString()}`;
    printDoc.body.appendChild(footer);
}


export function BulkQRPrintModal({ isOpen, onClose, items }: BulkQRPrintModalProps) {
    const [labels, setLabels] = useState<QRLabelData[]>([]);
    const [generating, setGenerating] = useState(false);

    // Generate QR codes for all items when the modal opens
    useEffect(() => {
        if (!isOpen || items.length === 0) {
            setLabels([]);
            return;
        }

        let cancelled = false;
        setGenerating(true);

        (async () => {
            const results: QRLabelData[] = [];
            for (const item of items) {
                if (cancelled) return;
                const data = encodeQRData(item.part_id, item.part_code ?? null);
                const dataUri = await QRCode.toDataURL(data, {
                    width: 200,
                    margin: 1,
                    color: { dark: '#000000', light: '#ffffff' },
                    errorCorrectionLevel: 'M',
                });
                results.push({ item, dataUri });
            }
            if (!cancelled) {
                setLabels(results);
                setGenerating(false);
            }
        })();

        return () => { cancelled = true; };
    }, [isOpen, items]);

    // ── Print handler ────────────────────────────────────────────
    const handlePrint = useCallback(() => {
        if (labels.length === 0) return;

        const printWindow = window.open('', '_blank', 'width=800,height=1000');
        if (!printWindow) return;

        buildBulkPrintPage(printWindow.document, labels);

        printWindow.onload = () => printWindow.print();
        setTimeout(() => {
            try { printWindow.print(); } catch { /* may be closed */ }
        }, 600);
    }, [labels]);

    return (
        <Modal isOpen={isOpen} onClose={onClose} title="Print QR Labels" size="lg">
            <div className="space-y-4">
                {/* Summary */}
                <div className="flex items-center gap-3">
                    <div className="p-2 rounded-lg bg-primary-50 dark:bg-primary-900/30">
                        <QrCode className="h-5 w-5 text-primary-500" />
                    </div>
                    <div>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                            {items.length} label{items.length !== 1 ? 's' : ''} ready to print
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                            Labels will print in a 2-column grid layout
                        </p>
                    </div>
                </div>

                {/* Preview grid */}
                {generating ? (
                    <div className="flex items-center justify-center py-8 gap-3">
                        <Loader2 className="h-5 w-5 animate-spin text-primary-500" />
                        <span className="text-sm text-gray-500 dark:text-gray-400">
                            Generating {items.length} QR codes...
                        </span>
                    </div>
                ) : (
                    <div className="max-h-80 overflow-y-auto border border-gray-200 dark:border-gray-700 rounded-lg p-3">
                        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                            {labels.map(({ item, dataUri }) => (
                                <div
                                    key={item.part_id}
                                    className="flex items-center gap-2 p-2 rounded-lg bg-gray-50 dark:bg-gray-800/50 border border-gray-100 dark:border-gray-700"
                                >
                                    <img
                                        src={dataUri}
                                        alt="QR"
                                        className="w-10 h-10 rounded flex-shrink-0"
                                        style={{ imageRendering: 'pixelated' }}
                                    />
                                    <div className="min-w-0">
                                        <p className="text-xs font-medium text-gray-900 dark:text-gray-100 truncate">
                                            {item.part_name}
                                        </p>
                                        {item.part_code && (
                                            <p className="text-[10px] text-gray-500 dark:text-gray-400 font-mono truncate">
                                                {item.part_code}
                                            </p>
                                        )}
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                )}
            </div>

            {/* Footer actions */}
            <div className="flex items-center gap-2 mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
                <Button
                    variant="primary"
                    icon={<Printer className="h-4 w-4" />}
                    onClick={handlePrint}
                    disabled={generating || labels.length === 0}
                >
                    Print {labels.length} Label{labels.length !== 1 ? 's' : ''}
                </Button>
                <Badge variant="default">2-column grid</Badge>
                <div className="flex-1" />
                <Button variant="ghost" onClick={onClose}>
                    <X className="h-4 w-4 mr-1" />
                    Close
                </Button>
            </div>
        </Modal>
    );
}
