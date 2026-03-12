/**
 * CommandPalette — Quick action launcher using cmdk.
 *
 * Opened via Ctrl+K or Ctrl+/ keyboard shortcut.
 * Searches across:
 *  - Navigation pages (all modules + tabs from navigation.ts)
 *  - Quick actions (New Order, Clock In, etc.)
 *
 * Inspired by VS Code's command palette. Uses the cmdk library for
 * fuzzy search and keyboard navigation.
 */

import { Command } from 'cmdk';
import { useNavigate } from 'react-router-dom';
import { useMemo, useCallback } from 'react';
import {
    Search,
    LayoutDashboard,
    Package,
    Building2,
    Warehouse,
    Truck,
    Briefcase,
    CalendarDays,
    BookOpen,
    MessageSquare,
    ShoppingCart,
    Users,
    Settings,
    Plus,
    Clock,
    FileText,
    Wrench,
} from 'lucide-react';
import { MODULES } from '../../lib/navigation';
import { useAuthStore } from '../../stores/auth-store';

interface CommandPaletteProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
}

/** Map module icon names to Lucide components */
const ICON_MAP: Record<string, React.ComponentType<{ className?: string }>> = {
    LayoutDashboard,
    Package,
    Building2,
    Warehouse,
    Truck,
    Briefcase,
    CalendarDays,
    BookOpen,
    MessageSquare,
    ShoppingCart,
    Users,
    Settings,
};

/** Quick actions available in the palette */
const QUICK_ACTIONS = [
    { id: 'new-order', label: 'New Order', path: '/orders/new-order', icon: Plus, group: 'Actions', permission: 'view_orders' },
    { id: 'clock-in', label: 'Clock In / Out', path: '/jobs/my-clock', icon: Clock, group: 'Actions', permission: 'view_jobs' },
    { id: 'daily-report', label: 'View Daily Reports', path: '/reports/daily-reports', icon: FileText, group: 'Actions', permission: 'view_reports' },
    { id: 'move-parts', label: 'Move Parts (Wizard)', path: '/warehouse/dashboard', icon: Warehouse, group: 'Actions', permission: 'view_warehouse' },
    { id: 'tool-checkout', label: 'Tool Checkout', path: '/warehouse/tools', icon: Wrench, group: 'Actions', permission: 'view_tools' },
];

export function CommandPalette({ open, onOpenChange }: CommandPaletteProps) {
    const navigate = useNavigate();
    const { hasPermission } = useAuthStore();

    // Build list of navigable items from MODULES
    const navItems = useMemo(() => {
        const items: { id: string; label: string; path: string; module: string; icon: string }[] = [];

        for (const mod of MODULES) {
            // Add the module itself
            items.push({
                id: `mod-${mod.id}`,
                label: mod.label,
                path: mod.path,
                module: mod.label,
                icon: mod.icon,
            });

            // Add each tab
            for (const tab of mod.tabs) {
                if (tab.permission && !hasPermission(tab.permission)) continue;
                items.push({
                    id: `tab-${mod.id}-${tab.id}`,
                    label: `${mod.label} → ${tab.label}`,
                    path: tab.path,
                    module: mod.label,
                    icon: mod.icon,
                });
            }
        }

        return items;
    }, [hasPermission]);

    // Filter quick actions by permission
    const actions = useMemo(
        () => QUICK_ACTIONS.filter((a) => !a.permission || hasPermission(a.permission)),
        [hasPermission]
    );

    const handleSelect = useCallback(
        (path: string) => {
            onOpenChange(false);
            navigate(path);
        },
        [navigate, onOpenChange]
    );

    if (!open) return null;

    return (
        <div className="fixed inset-0 z-[100]" onClick={() => onOpenChange(false)}>
            {/* Backdrop */}
            <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />

            {/* Dialog */}
            <div
                className="absolute top-[20%] left-1/2 -translate-x-1/2 w-[90vw] max-w-lg"
                onClick={(e) => e.stopPropagation()}
            >
                <Command
                    className="rounded-xl border border-border bg-surface shadow-2xl overflow-hidden"
                    label="Command Palette"
                >
                    {/* Search input */}
                    <div className="flex items-center gap-2 border-b border-border px-4 py-3">
                        <Search className="h-4 w-4 text-gray-400 flex-shrink-0" />
                        <Command.Input
                            placeholder="Search pages, actions…"
                            className="flex-1 bg-transparent text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 outline-none"
                            autoFocus
                        />
                        <kbd className="hidden sm:inline-flex items-center gap-1 rounded bg-gray-100 dark:bg-gray-800 px-1.5 py-0.5 text-[10px] font-mono text-gray-500">
                            ESC
                        </kbd>
                    </div>

                    {/* Results list */}
                    <Command.List className="max-h-[50vh] overflow-y-auto p-2">
                        <Command.Empty className="py-6 text-center text-sm text-gray-500 dark:text-gray-400">
                            No results found.
                        </Command.Empty>

                        {/* Quick Actions */}
                        {actions.length > 0 && (
                            <Command.Group heading="Quick Actions" className="mb-2">
                                {actions.map((action) => (
                                    <Command.Item
                                        key={action.id}
                                        value={action.label}
                                        onSelect={() => handleSelect(action.path)}
                                        className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm cursor-pointer text-gray-700 dark:text-gray-300 data-[selected=true]:bg-primary/10 data-[selected=true]:text-primary transition-colors"
                                    >
                                        <action.icon className="h-4 w-4 flex-shrink-0 text-gray-400" />
                                        <span>{action.label}</span>
                                    </Command.Item>
                                ))}
                            </Command.Group>
                        )}

                        {/* Navigation Pages */}
                        <Command.Group heading="Pages" className="mb-2">
                            {navItems.map((item) => {
                                const IconComponent = ICON_MAP[item.icon];
                                return (
                                    <Command.Item
                                        key={item.id}
                                        value={item.label}
                                        onSelect={() => handleSelect(item.path)}
                                        className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm cursor-pointer text-gray-700 dark:text-gray-300 data-[selected=true]:bg-primary/10 data-[selected=true]:text-primary transition-colors"
                                    >
                                        {IconComponent ? (
                                            <IconComponent className="h-4 w-4 flex-shrink-0 text-gray-400" />
                                        ) : (
                                            <div className="h-4 w-4" />
                                        )}
                                        <span>{item.label}</span>
                                    </Command.Item>
                                );
                            })}
                        </Command.Group>
                    </Command.List>

                    {/* Footer hint */}
                    <div className="border-t border-border px-4 py-2 flex items-center justify-between text-[11px] text-gray-400">
                        <span>
                            <kbd className="font-mono">↑↓</kbd> navigate · <kbd className="font-mono">Enter</kbd> select
                        </span>
                        <span>
                            <kbd className="font-mono">Ctrl+K</kbd> to toggle
                        </span>
                    </div>
                </Command>
            </div>
        </div>
    );
}
