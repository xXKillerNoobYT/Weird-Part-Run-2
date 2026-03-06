/**
 * ContactDirectoryPage — unified search across all entity contacts.
 *
 * Searches entity_contacts for customers, general contractors, and suppliers in
 * one place. Shows contact name, role, phone, email, and a badge for entity type.
 * Click navigates to the parent entity's detail page.
 *
 * Simple search-focused page — no filters, no pagination (API returns top matches).
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Search, Phone, Mail, X, BookUser, Building2, HardHat, Package,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { searchDirectory } from '../../../api/contacts';
import type { DirectoryContactResult, EntityType } from '../../../lib/types';


// ── Helpers ───────────────────────────────────────────────────────

const ENTITY_TYPE_LABELS: Record<EntityType, string> = {
  customer: 'Customer',
  general_contractor: 'Contractor',
  supplier: 'Supplier',
};

const ENTITY_TYPE_BADGE: Record<EntityType, 'primary' | 'warning' | 'info'> = {
  customer: 'primary',
  general_contractor: 'warning',
  supplier: 'info',
};

const ENTITY_TYPE_ICON: Record<EntityType, typeof Building2> = {
  customer: Building2,
  general_contractor: HardHat,
  supplier: Package,
};

/** Map entity_type → route for detail page */
function entityDetailRoute(type: EntityType, id: number): string {
  switch (type) {
    case 'customer': return `/people/customers/${id}`;
    case 'general_contractor': return `/people/contractors/${id}`;
    case 'supplier': return `/warehouse/suppliers`; // suppliers don't have individual detail page
  }
}


// ═════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════

export function ContactDirectoryPage() {
  const navigate = useNavigate();

  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // ── Query ──────────────────────────────────────────────────────
  const { data: contacts, isLoading } = useQuery({
    queryKey: ['directory', debouncedSearch],
    queryFn: () => searchDirectory(debouncedSearch),
    enabled: debouncedSearch.length >= 2,
    staleTime: 10_000,
  });

  return (
    <div className="space-y-4">
      {/* Header */}
      <div>
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          All Contacts
        </h1>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Search across customers, contractors, and suppliers
        </p>
      </div>

      {/* Search */}
      <Input
        placeholder="Search contacts by name, role, phone, or email..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        icon={<Search size={16} />}
        iconRight={search ? (
          <button onClick={() => setSearch('')} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
            <X size={14} />
          </button>
        ) : undefined}
        autoFocus
      />

      {/* Results */}
      {debouncedSearch.length < 2 ? (
        <EmptyState
          icon={<BookUser size={48} />}
          title="Type to search"
          description="Enter at least 2 characters to search all contacts across customers, contractors, and suppliers."
        />
      ) : isLoading ? (
        <PageSpinner label="Searching..." />
      ) : !contacts || contacts.length === 0 ? (
        <EmptyState
          icon={<BookUser size={48} />}
          title="No contacts found"
          description={`No results for "${debouncedSearch}". Try a different search term.`}
        />
      ) : (
        <div className="space-y-2">
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {contacts.length} contact{contacts.length !== 1 ? 's' : ''} found
          </p>
          {contacts.map((contact) => (
            <DirectoryRow
              key={`${contact.entity_type}-${contact.id}`}
              contact={contact}
              onClick={() => navigate(entityDetailRoute(contact.entity_type, contact.entity_id))}
            />
          ))}
        </div>
      )}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Directory Row
// ═════════════════════════════════════════════════════════════════

function DirectoryRow({
  contact,
  onClick,
}: {
  contact: DirectoryContactResult;
  onClick: () => void;
}) {
  const Icon = ENTITY_TYPE_ICON[contact.entity_type];

  return (
    <Card noPadding>
      <button
        onClick={onClick}
        className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors rounded-lg"
      >
        {/* Icon */}
        <div className="flex-shrink-0 w-10 h-10 rounded-full bg-gray-100 dark:bg-gray-700 flex items-center justify-center text-gray-500 dark:text-gray-400">
          <Icon size={18} />
        </div>

        {/* Contact info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-gray-100">
              {contact.first_name} {contact.last_name}
            </span>
            <Badge variant={ENTITY_TYPE_BADGE[contact.entity_type]}>
              {ENTITY_TYPE_LABELS[contact.entity_type]}
            </Badge>
          </div>
          <div className="flex items-center gap-3 mt-0.5 text-xs text-gray-500 dark:text-gray-400">
            <span>{contact.role}</span>
            <span className="hidden sm:inline">·</span>
            <span className="hidden sm:inline truncate">{contact.entity_name}</span>
          </div>
        </div>

        {/* Phone and email */}
        <div className="flex items-center gap-3 text-sm text-gray-500 dark:text-gray-400 flex-shrink-0">
          {contact.phone && (
            <span className="flex items-center gap-1">
              <Phone size={14} />
              <span className="hidden md:inline truncate max-w-[120px]">{contact.phone}</span>
            </span>
          )}
          {contact.email && (
            <span className="hidden md:flex items-center gap-1">
              <Mail size={14} />
              <span className="truncate max-w-[160px]">{contact.email}</span>
            </span>
          )}
        </div>
      </button>
    </Card>
  );
}
