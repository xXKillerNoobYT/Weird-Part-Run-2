/**
 * QRLabelModal — generate and print QR code labels for warehouse parts.
 *
 * Shows the QR code + full part details, with options to:
 * - Print the label (opens a clean print window)
 * - Mark the part as "QR tagged" in the database
 * - Remove the QR tag
 */

import { useState, useEffect } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import QRCode from 'qrcode';
import { Printer, Tag, X, QrCode } from 'lucide-react';
import { Modal } from '../../../../components/ui/Modal';
import { Button } from '../../../../components/ui/Button';
import { encodeQRData } from '../../../../lib/qr-utils';
import { updatePart } from '../../../../api/parts';
import type { WarehouseInventoryItem } from '../../../../lib/types';

interface QRLabelModalProps {
  isOpen: boolean;
  onClose: () => void;
  item: WarehouseInventoryItem | null;
}

/** Build the print-ready label page content via DOM APIs. */
function buildPrintPage(
  printDoc: Document,
  item: WarehouseInventoryItem,
  qrDataUri: string,
) {
  const style = printDoc.createElement('style');
  style.textContent = `
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      padding: 24px; max-width: 400px; margin: 0 auto;
    }
    .qr-container { text-align: center; padding: 16px 0; }
    .qr-container img { width: 200px; height: 200px; image-rendering: pixelated; }
    .details { border-top: 2px solid #111; padding-top: 12px; margin-top: 8px; }
    .part-name { font-size: 16px; font-weight: 700; margin-bottom: 8px; }
    .detail-row { display: flex; gap: 8px; padding: 3px 0; font-size: 12px; border-bottom: 1px solid #eee; }
    .detail-row:last-child { border-bottom: none; }
    .detail-label { color: #666; font-weight: 600; min-width: 70px; flex-shrink: 0; }
    .detail-value { color: #111; }
    .footer { margin-top: 12px; text-align: center; font-size: 10px; color: #999; }
    @media print { body { padding: 12px; } .qr-container img { width: 180px; height: 180px; } }
  `;
  printDoc.head.appendChild(style);
  printDoc.title = `QR Label - ${item.part_name}`;

  // QR code image
  const qrContainer = printDoc.createElement('div');
  qrContainer.className = 'qr-container';
  const img = printDoc.createElement('img');
  img.src = qrDataUri;
  img.alt = 'QR Code';
  qrContainer.appendChild(img);
  printDoc.body.appendChild(qrContainer);

  // Part details
  const details = printDoc.createElement('div');
  details.className = 'details';

  const nameEl = printDoc.createElement('div');
  nameEl.className = 'part-name';
  nameEl.textContent = item.part_name;
  details.appendChild(nameEl);

  const addRow = (label: string, value: string) => {
    const row = printDoc.createElement('div');
    row.className = 'detail-row';
    const labelEl = printDoc.createElement('span');
    labelEl.className = 'detail-label';
    labelEl.textContent = label;
    const valueEl = printDoc.createElement('span');
    valueEl.className = 'detail-value';
    valueEl.textContent = value;
    row.appendChild(labelEl);
    row.appendChild(valueEl);
    details.appendChild(row);
  };

  if (item.part_code) addRow('Code', item.part_code);
  if (item.category_name) addRow('Category', item.category_name);
  if (item.brand_name) addRow('Brand', item.brand_name);
  if (item.shelf_location) addRow('Shelf', item.shelf_location);
  if (item.bin_location) addRow('Bin', item.bin_location);
  addRow('Unit', item.unit_of_measure);

  printDoc.body.appendChild(details);

  // Footer
  const footer = printDoc.createElement('div');
  footer.className = 'footer';
  footer.textContent = 'Wired-Part Inventory Label';
  printDoc.body.appendChild(footer);
}

export function QRLabelModal({ isOpen, onClose, item }: QRLabelModalProps) {
  const queryClient = useQueryClient();
  const [qrDataUri, setQrDataUri] = useState<string | null>(null);

  // Local tag state — syncs from prop, toggles optimistically on mutation
  const [isTagged, setIsTagged] = useState(false);
  useEffect(() => {
    if (item) setIsTagged(!!item.is_qr_tagged);
  }, [item]);

  // Generate QR code when item changes
  useEffect(() => {
    if (!item) {
      setQrDataUri(null);
      return;
    }

    const data = encodeQRData(item.part_id, item.part_code ?? null);
    QRCode.toDataURL(data, {
      width: 256,
      margin: 2,
      color: { dark: '#000000', light: '#ffffff' },
      errorCorrectionLevel: 'M',
    }).then(setQrDataUri);
  }, [item]);

  // ── Tag toggle mutation ──────────────────────────────────────
  const { mutate: toggleTag, isPending: isTagging } = useMutation({
    mutationFn: () => {
      if (!item) throw new Error('No item');
      return updatePart(item.part_id, {
        is_qr_tagged: !isTagged,
      });
    },
    onSuccess: () => {
      setIsTagged((prev) => !prev);
      queryClient.invalidateQueries({ queryKey: ['warehouse-inventory'] });
    },
  });

  // ── Print handler ────────────────────────────────────────────
  const handlePrint = () => {
    if (!item || !qrDataUri) return;

    const printWindow = window.open('', '_blank', 'width=450,height=650');
    if (!printWindow) return;

    buildPrintPage(printWindow.document, item, qrDataUri);

    // Wait for the image to load, then trigger print
    printWindow.onload = () => {
      printWindow.print();
    };
    // Fallback: trigger print after a short delay (onload doesn't fire in all browsers for about:blank)
    setTimeout(() => {
      try { printWindow.print(); } catch { /* window may have been closed */ }
    }, 500);
  };

  if (!item) return null;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="QR Label" size="sm">
      <div className="space-y-4">
        {/* QR Code */}
        <div className="flex justify-center py-2">
          {qrDataUri ? (
            <img
              src={qrDataUri}
              alt="QR Code"
              className="w-48 h-48 rounded-lg border border-gray-200 dark:border-gray-700 bg-white p-2"
              style={{ imageRendering: 'pixelated' }}
            />
          ) : (
            <div className="w-48 h-48 rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 flex items-center justify-center">
              <QrCode className="h-12 w-12 text-gray-300 dark:text-gray-600" />
            </div>
          )}
        </div>

        {/* Part Details */}
        <div className="space-y-1.5 px-2">
          <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            {item.part_name}
          </h3>

          <div className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
            {item.part_code && (
              <>
                <span className="text-gray-500 dark:text-gray-400">Code</span>
                <span className="font-mono text-gray-900 dark:text-gray-100">{item.part_code}</span>
              </>
            )}
            {item.category_name && (
              <>
                <span className="text-gray-500 dark:text-gray-400">Category</span>
                <span className="text-gray-900 dark:text-gray-100">{item.category_name}</span>
              </>
            )}
            {item.brand_name && (
              <>
                <span className="text-gray-500 dark:text-gray-400">Brand</span>
                <span className="text-gray-900 dark:text-gray-100">{item.brand_name}</span>
              </>
            )}
            {item.shelf_location && (
              <>
                <span className="text-gray-500 dark:text-gray-400">Shelf</span>
                <span className="text-gray-900 dark:text-gray-100">{item.shelf_location}</span>
              </>
            )}
            {item.bin_location && (
              <>
                <span className="text-gray-500 dark:text-gray-400">Bin</span>
                <span className="text-gray-900 dark:text-gray-100">{item.bin_location}</span>
              </>
            )}
            <span className="text-gray-500 dark:text-gray-400">Stock</span>
            <span className="text-gray-900 dark:text-gray-100">
              {item.warehouse_qty} {item.unit_of_measure}
            </span>
          </div>
        </div>

        {/* QR Tagged status */}
        {isTagged && (
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800">
            <Tag className="h-3.5 w-3.5 text-green-600 dark:text-green-400" />
            <span className="text-xs font-medium text-green-700 dark:text-green-300">
              QR Tagged
            </span>
          </div>
        )}
      </div>

      {/* Footer actions */}
      <div className="flex flex-wrap items-center gap-2 mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <Button
          variant="primary"
          size="sm"
          icon={<Printer className="h-3.5 w-3.5" />}
          onClick={handlePrint}
          disabled={!qrDataUri}
        >
          Print Label
        </Button>

        <Button
          variant={isTagged ? 'ghost' : 'secondary'}
          size="sm"
          icon={
            isTagged
              ? <X className="h-3.5 w-3.5" />
              : <Tag className="h-3.5 w-3.5" />
          }
          onClick={() => toggleTag()}
          isLoading={isTagging}
        >
          {isTagged ? 'Remove Tag' : 'Mark as Tagged'}
        </Button>

        <div className="flex-1" />
        <Button variant="ghost" size="sm" onClick={onClose}>
          Close
        </Button>
      </div>
    </Modal>
  );
}
