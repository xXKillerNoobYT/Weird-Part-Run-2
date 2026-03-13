/**
 * PDFSettingsPage — configure PO PDF document template.
 *
 * Controls how generated PO PDFs look: accent color, which columns
 * are visible, footer text, payment terms, and default delivery notes.
 * Also allows uploading/replacing the company logo that appears on PDFs.
 *
 * Company name/address/contact info comes from Company Profiles
 * (separate page) — this page only controls PDF-specific formatting.
 */

import { useState, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    FileText, Upload, Palette, RotateCcw,
    Check, AlertCircle, ImageIcon,
} from 'lucide-react';
import {
    getPDFSettings,
    updatePDFSettings,
    uploadCompanyLogo,
    listCompanyProfiles,
} from '../../../api/settings';
import type { PDFSettings } from '../../../lib/types';

/** Defaults to reset to. */
const PDF_DEFAULTS: PDFSettings = {
    accent_color: '#3B82F6',
    show_unit_prices: true,
    show_extended: true,
    footer_text: '',
    payment_terms: 'Net 30',
    delivery_notes: '',
};

export function PDFSettingsPage() {
    const queryClient = useQueryClient();
    const fileInputRef = useRef<HTMLInputElement>(null);
    const [logoUploading, setLogoUploading] = useState(false);
    const [logoError, setLogoError] = useState<string | null>(null);
    const [saveSuccess, setSaveSuccess] = useState(false);

    // ── Queries ──────────────────────────────────────────────

    const settingsQ = useQuery({
        queryKey: ['pdf-settings'],
        queryFn: getPDFSettings,
    });

    const companyQ = useQuery({
        queryKey: ['company-profiles'],
        queryFn: listCompanyProfiles,
    });

    // Local form state — initialized from server data
    const [form, setForm] = useState<PDFSettings | null>(null);

    // Use server data as initial form state
    const currentSettings = form ?? settingsQ.data ?? PDF_DEFAULTS;
    if (!form && settingsQ.data) {
        // First load — initialize form from server
        setForm(settingsQ.data);
    }

    const primaryCompany = companyQ.data?.find((p) => p.is_primary) ?? companyQ.data?.[0];

    // ── Mutations ────────────────────────────────────────────

    const saveMut = useMutation({
        mutationFn: (data: PDFSettings) => updatePDFSettings(data),
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['pdf-settings'] });
            setForm(data);
            setSaveSuccess(true);
            setTimeout(() => setSaveSuccess(false), 3000);
        },
    });

    const logoMut = useMutation({
        mutationFn: uploadCompanyLogo,
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['company-profiles'] });
            setLogoUploading(false);
            setLogoError(null);
        },
        onError: (e: Error) => {
            setLogoUploading(false);
            setLogoError(e.message || 'Failed to upload logo');
        },
    });

    // ── Handlers ─────────────────────────────────────────────

    function handleChange<K extends keyof PDFSettings>(key: K, value: PDFSettings[K]) {
        setForm((prev) => ({ ...(prev ?? PDF_DEFAULTS), [key]: value }));
    }

    function handleSave() {
        if (!form) return;
        saveMut.mutate(form);
    }

    function handleReset() {
        setForm(PDF_DEFAULTS);
    }

    function handleLogoClick() {
        fileInputRef.current?.click();
    }

    async function handleLogoChange(e: React.ChangeEvent<HTMLInputElement>) {
        const file = e.target.files?.[0];
        if (!file) return;

        // Client-side validation
        const validTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/svg+xml', 'image/webp'];
        if (!validTypes.includes(file.type)) {
            setLogoError('Please upload a PNG, JPG, GIF, SVG, or WebP image');
            return;
        }
        if (file.size > 5 * 1024 * 1024) {
            setLogoError('Logo must be under 5 MB');
            return;
        }

        setLogoUploading(true);
        setLogoError(null);
        logoMut.mutate(file);

        // Reset file input
        if (fileInputRef.current) fileInputRef.current.value = '';
    }

    const isDirty = form && JSON.stringify(form) !== JSON.stringify(settingsQ.data);

    // ── Loading State ────────────────────────────────────────

    if (settingsQ.isLoading) {
        return (
            <div className="flex items-center justify-center py-12">
                <div className="animate-spin w-6 h-6 border-2 border-blue-500 border-t-transparent rounded-full" />
            </div>
        );
    }

    // ── Render ───────────────────────────────────────────────

    return (
        <div className="space-y-6 max-w-3xl">
            {/* Header */}
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                    <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
                        PDF & Documents
                    </h1>
                    <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                        Customize how PO documents look when generated as PDFs or copied as text.
                    </p>
                </div>
            </div>

            {/* Success Banner */}
            {saveSuccess && (
                <div className="flex items-center gap-2 p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg text-green-700 dark:text-green-300 text-sm">
                    <Check className="w-4 h-4 shrink-0" />
                    Settings saved successfully.
                </div>
            )}

            {/* Error Banner */}
            {saveMut.isError && (
                <div className="flex items-center gap-2 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-red-700 dark:text-red-300 text-sm">
                    <AlertCircle className="w-4 h-4 shrink-0" />
                    {(saveMut.error as Error)?.message || 'Failed to save settings.'}
                </div>
            )}

            {/* ── Company Logo Section ──────────────────────────── */}
            <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-5">
                <div className="flex items-center gap-2 mb-4">
                    <ImageIcon className="w-5 h-5 text-gray-400" />
                    <h2 className="text-base font-medium text-gray-900 dark:text-gray-100">
                        Company Logo
                    </h2>
                </div>
                <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
                    This logo appears in the top-left of every PO PDF. Recommended: PNG or SVG, at least 200×200px.
                </p>

                <div className="flex items-center gap-4">
                    {/* Logo preview */}
                    <div
                        className="w-24 h-24 border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg flex items-center justify-center overflow-hidden bg-gray-50 dark:bg-gray-700 shrink-0 cursor-pointer"
                        onClick={handleLogoClick}
                    >
                        {primaryCompany?.logo_path ? (
                            <img
                                src={`/uploads/logos/${primaryCompany.logo_path.split('/').pop()}`}
                                alt="Company logo"
                                className="w-full h-full object-contain"
                                onError={(e) => {
                                    (e.target as HTMLImageElement).style.display = 'none';
                                }}
                            />
                        ) : (
                            <ImageIcon className="w-8 h-8 text-gray-400" />
                        )}
                    </div>

                    <div className="space-y-2">
                        <button
                            onClick={handleLogoClick}
                            disabled={logoUploading}
                            className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-50"
                        >
                            <Upload className="w-4 h-4" />
                            {logoUploading ? 'Uploading...' : primaryCompany?.logo_path ? 'Replace Logo' : 'Upload Logo'}
                        </button>
                        <p className="text-xs text-gray-400">PNG, JPG, SVG, WebP · Max 5 MB</p>
                    </div>

                    <input
                        ref={fileInputRef}
                        type="file"
                        accept="image/png,image/jpeg,image/gif,image/svg+xml,image/webp"
                        onChange={handleLogoChange}
                        className="hidden"
                    />
                </div>

                {logoError && (
                    <p className="mt-2 text-sm text-red-600 dark:text-red-400">{logoError}</p>
                )}
            </div>

            {/* ── Accent Color ──────────────────────────────────── */}
            <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-5">
                <div className="flex items-center gap-2 mb-4">
                    <Palette className="w-5 h-5 text-gray-400" />
                    <h2 className="text-base font-medium text-gray-900 dark:text-gray-100">
                        Accent Color
                    </h2>
                </div>
                <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
                    Used for the header bar and table heading background in PO PDFs.
                </p>

                <div className="flex items-center gap-3">
                    <input
                        type="color"
                        value={currentSettings.accent_color}
                        onChange={(e) => handleChange('accent_color', e.target.value)}
                        className="w-10 h-10 rounded border border-gray-300 dark:border-gray-600 cursor-pointer"
                    />
                    <input
                        type="text"
                        value={currentSettings.accent_color}
                        onChange={(e) => handleChange('accent_color', e.target.value)}
                        className="w-28 px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 font-mono"
                        placeholder="#3B82F6"
                        maxLength={7}
                    />
                    {/* Preview swatch */}
                    <div
                        className="h-10 flex-1 rounded-lg"
                        style={{ backgroundColor: currentSettings.accent_color }}
                    />
                </div>
            </div>

            {/* ── Column Visibility ─────────────────────────────── */}
            <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-5">
                <div className="flex items-center gap-2 mb-4">
                    <FileText className="w-5 h-5 text-gray-400" />
                    <h2 className="text-base font-medium text-gray-900 dark:text-gray-100">
                        Line Item Columns
                    </h2>
                </div>
                <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
                    Choose which price columns to include in the PO PDF line items table.
                    Hiding prices is useful when sending POs that shouldn't show cost details.
                </p>

                <div className="space-y-3">
                    <ToggleRow
                        label="Show Unit Prices"
                        description='Include the "Unit $" column'
                        enabled={currentSettings.show_unit_prices}
                        onChange={(v) => handleChange('show_unit_prices', v)}
                    />
                    <ToggleRow
                        label="Show Extended Totals"
                        description='Include the "Total $" column (Qty × Unit)'
                        enabled={currentSettings.show_extended}
                        onChange={(v) => handleChange('show_extended', v)}
                    />
                </div>
            </div>

            {/* ── Text Defaults ─────────────────────────────────── */}
            <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-5 space-y-4">
                <div className="flex items-center gap-2">
                    <FileText className="w-5 h-5 text-gray-400" />
                    <h2 className="text-base font-medium text-gray-900 dark:text-gray-100">
                        Default Text
                    </h2>
                </div>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                    These defaults appear on every PO unless overridden per order.
                </p>

                <TextAreaField
                    label="Payment Terms"
                    value={currentSettings.payment_terms}
                    onChange={(v) => handleChange('payment_terms', v)}
                    placeholder="e.g. Net 30"
                    rows={1}
                />

                <TextAreaField
                    label="Default Delivery Instructions"
                    value={currentSettings.delivery_notes}
                    onChange={(v) => handleChange('delivery_notes', v)}
                    placeholder="e.g. Deliver to warehouse loading dock, call before arrival"
                    rows={2}
                />

                <TextAreaField
                    label="Footer Text"
                    value={currentSettings.footer_text}
                    onChange={(v) => handleChange('footer_text', v)}
                    placeholder='e.g. "Thank you for your business!"'
                    rows={2}
                />
            </div>

            {/* ── Action Buttons ────────────────────────────────── */}
            <div className="flex flex-wrap items-center gap-3">
                <button
                    onClick={handleSave}
                    disabled={saveMut.isPending || !isDirty}
                    className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed"
                >
                    <Check className="w-4 h-4" />
                    {saveMut.isPending ? 'Saving...' : 'Save Settings'}
                </button>

                <button
                    onClick={handleReset}
                    className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700"
                >
                    <RotateCcw className="w-4 h-4" />
                    Reset to Defaults
                </button>
            </div>
        </div>
    );
}


// ── Subcomponents ──────────────────────────────────────────

function ToggleRow({
    label,
    description,
    enabled,
    onChange,
}: {
    label: string;
    description: string;
    enabled: boolean;
    onChange: (v: boolean) => void;
}) {
    return (
        <label className="flex items-center justify-between gap-4 py-2 cursor-pointer">
            <div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">{label}</p>
                <p className="text-xs text-gray-500 dark:text-gray-400">{description}</p>
            </div>
            <button
                type="button"
                role="switch"
                aria-checked={enabled}
                onClick={() => onChange(!enabled)}
                className={`relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent transition-colors ${enabled ? 'bg-blue-600' : 'bg-gray-300 dark:bg-gray-600'
                    }`}
            >
                <span
                    className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow transition-transform ${enabled ? 'translate-x-5' : 'translate-x-0'
                        }`}
                />
            </button>
        </label>
    );
}


function TextAreaField({
    label,
    value,
    onChange,
    placeholder,
    rows = 2,
}: {
    label: string;
    value: string;
    onChange: (v: string) => void;
    placeholder?: string;
    rows?: number;
}) {
    return (
        <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                {label}
            </label>
            <textarea
                value={value}
                onChange={(e) => onChange(e.target.value)}
                placeholder={placeholder}
                rows={rows}
                className="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 placeholder:text-gray-400 resize-y"
            />
        </div>
    );
}
