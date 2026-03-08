import { Link2, Building2, Users, ShieldCheck, Network, Boxes, FileText, PlugZap } from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';

const PHASES = [
    {
        phase: 'Phase S1',
        title: 'Communication Bridge Core',
        status: 'planned',
        items: [
            'Supplier-side login mode (communication-first, not ERP replacement)',
            'Contractor ↔ Supplier partner channels for PO + RFI communication',
            'Rich attachments (PDF/photos/videos/docs) with clear context',
            'Optional quick-link sharing (supplier part links + references)',
        ],
    },
    {
        phase: 'Phase S2',
        title: 'Supplier Suggest Catalog (Backup)',
        status: 'planned',
        items: [
            'Rep-level lightweight catalog for frequently suggested parts',
            'Price sharing OFF by default',
            'One-click “Send to Contractor” from suggest catalog',
            'Contractor-side “Import Part” flow to create internal part + supplier mapping',
        ],
    },
    {
        phase: 'Phase S3',
        title: 'Optional Supplier API Connectors',
        status: 'planned',
        items: [
            'Pluggable connector layer for supplier catalog APIs',
            'Versioned mapping by supplier part ID / supplier org ID',
            'Live availability/pricing optional and guarded by capability flags',
            'Integration contracts designed so either side can evolve independently',
        ],
    },
    {
        phase: 'Phase S4',
        title: 'Remote Pairing + Recovery',
        status: 'planned',
        items: [
            'Shop identity + known-partner records',
            'Automatic one-sided IP recovery',
            'Guided manual recovery when both IPs change',
            'Certificate/PIN validation for secure re-linking',
        ],
    },
];

function PhaseCard({
    phase,
    title,
    status,
    items,
}: {
    phase: string;
    title: string;
    status: 'planned' | 'in-progress' | 'done';
    items: string[];
}) {
    const variant = status === 'done' ? 'success' : status === 'in-progress' ? 'warning' : 'default';
    const statusLabel = status === 'done' ? 'Done' : status === 'in-progress' ? 'In Progress' : 'Planned';

    return (
        <Card>
            <div className="p-4 space-y-3">
                <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div>
                        <p className="text-xs uppercase tracking-wide text-gray-400">{phase}</p>
                        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{title}</h3>
                    </div>
                    <Badge variant={variant}>{statusLabel}</Badge>
                </div>

                <ul className="space-y-1.5">
                    {items.map((item, idx) => (
                        <li key={idx} className="text-sm text-gray-700 dark:text-gray-300 flex gap-2">
                            <span className="text-gray-400">•</span>
                            <span>{item}</span>
                        </li>
                    ))}
                </ul>
            </div>
        </Card>
    );
}

export function SupplierBridgePage() {
    return (
        <div className="space-y-5">
            <div>
                <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                    <Link2 className="h-5 w-5 text-indigo-500" />
                    Supplier Communication Bridge
                </h2>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
                    Communication-first supplier integration roadmap: PO/RFI messaging, part suggestions,
                    optional API connectors, and resilient partner pairing.
                </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                <MiniPill icon={<Building2 className="h-4 w-4" />} label="Supplier App Mode" />
                <MiniPill icon={<Users className="h-4 w-4" />} label="Multi-Customer Support" />
                <MiniPill icon={<Network className="h-4 w-4" />} label="Dynamic IP Recovery" />
                <MiniPill icon={<ShieldCheck className="h-4 w-4" />} label="Secure Pairing" />
            </div>

            <Card>
                <div className="p-4 space-y-3">
                    <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Design Guardrails</h3>
                    <ul className="space-y-1.5 text-sm text-gray-700 dark:text-gray-300">
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>This does <strong>not</strong> replace supplier ERP systems; it is a communication bridge.</span></li>
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>Price sharing remains <strong>off by default</strong>; live pricing is optional via API connectors.</span></li>
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>Attachment-first communication for PO/RFI context (PDFs, photos, videos, docs, links).</span></li>
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>Supplier-sent parts should be importable into contractor catalog with supplier mapping metadata.</span></li>
                    </ul>
                </div>
            </Card>

            <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
                {PHASES.map((p) => (
                    <PhaseCard
                        key={p.phase}
                        phase={p.phase}
                        title={p.title}
                        status={p.status as 'planned' | 'in-progress' | 'done'}
                        items={p.items}
                    />
                ))}
            </div>

            <Card>
                <div className="p-4 space-y-2">
                    <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Planned Feature Areas</h3>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm text-gray-700 dark:text-gray-300">
                        <div className="flex items-center gap-2"><Boxes className="h-4 w-4 text-gray-500" /> Supplier Suggest Catalog</div>
                        <div className="flex items-center gap-2"><PlugZap className="h-4 w-4 text-gray-500" /> API Connector Framework</div>
                        <div className="flex items-center gap-2"><FileText className="h-4 w-4 text-gray-500" /> PO/RFI Attachment Channels</div>
                        <div className="flex items-center gap-2"><ShieldCheck className="h-4 w-4 text-gray-500" /> Partner Recovery Wizard</div>
                    </div>
                </div>
            </Card>
        </div>
    );
}

function MiniPill({ icon, label }: { icon: React.ReactNode; label: string }) {
    return (
        <div className="min-h-11 px-3 py-2 rounded-lg border border-border bg-surface flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <span className="text-gray-500">{icon}</span>
            <span>{label}</span>
        </div>
    );
}
