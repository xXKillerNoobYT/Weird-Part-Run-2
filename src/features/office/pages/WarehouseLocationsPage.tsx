/**
 * WarehouseLocationsPage — manage shop/warehouse physical addresses.
 *
 * Company shops and warehouses are the anchor points for mileage estimation
 * (drivers commute Home → Shop, then Shop → Job). This CRUD page lets fleet
 * managers maintain the list of physical locations.
 *
 * Accessible via Office > Warehouse Locations tab (requires manage_fleet permission).
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  MapPin,
  Plus,
  Pencil,
  Trash2,
  Star,
  Building2,
  Phone,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import {
  listWarehouseLocations,
  createWarehouseLocation,
  updateWarehouseLocation,
  deactivateWarehouseLocation,
} from '../../../api/vehicles';
import type { WarehouseLocation, WarehouseLocationCreate, WarehouseLocationUpdate } from '../../../lib/types';


export function WarehouseLocationsPage() {
  const queryClient = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);
  const [editingLocation, setEditingLocation] = useState<WarehouseLocation | null>(null);
  const [showInactive, setShowInactive] = useState(false);

  const { data: locations, isLoading, error } = useQuery({
    queryKey: ['warehouse-locations', showInactive],
    queryFn: () => listWarehouseLocations({ include_inactive: showInactive || undefined }),
    staleTime: 30_000,
  });

  const deactivateMut = useMutation({
    mutationFn: (id: number) => deactivateWarehouseLocation(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['warehouse-locations'] }),
  });

  if (isLoading) return <PageSpinner label="Loading locations..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load warehouse locations.</p>
      </div>
    );
  }

  const activeLocations = locations?.filter((l) => l.is_active) ?? [];
  const inactiveLocations = locations?.filter((l) => !l.is_active) ?? [];

  return (
    <div className="space-y-4">
      {/* ── Header ── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Warehouse Locations
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Manage shop and warehouse addresses used for mileage estimation.
          </p>
        </div>
        <div className="flex items-center gap-2">
          {inactiveLocations.length > 0 && (
            <Button
              size="sm"
              variant={showInactive ? 'primary' : 'secondary'}
              onClick={() => setShowInactive(!showInactive)}
            >
              {showInactive ? 'Hide' : 'Show'} Inactive ({inactiveLocations.length})
            </Button>
          )}
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setShowCreate(true)}
          >
            <span className="hidden sm:inline">Add Location</span>
          </Button>
        </div>
      </div>

      {/* ── Location Cards ── */}
      {!locations || activeLocations.length === 0 ? (
        <EmptyState
          icon={<MapPin className="h-12 w-12" />}
          title="No Locations"
          description="Add your first shop or warehouse address to enable mileage estimation."
          action={
            <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowCreate(true)}>
              Add Location
            </Button>
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {(showInactive ? locations : activeLocations)?.map((loc) => (
            <LocationCard
              key={loc.id}
              location={loc}
              onEdit={() => setEditingLocation(loc)}
              onDeactivate={() => {
                if (confirm(`Deactivate "${loc.name}"? This won't delete it.`)) {
                  deactivateMut.mutate(loc.id);
                }
              }}
            />
          ))}
        </div>
      )}

      {/* ── Create Modal ── */}
      <LocationFormModal
        isOpen={showCreate}
        onClose={() => setShowCreate(false)}
        mode="create"
      />

      {/* ── Edit Modal ── */}
      {editingLocation && (
        <LocationFormModal
          isOpen={true}
          onClose={() => setEditingLocation(null)}
          mode="edit"
          location={editingLocation}
        />
      )}
    </div>
  );
}


// ── Location Card ─────────────────────────────────────────────────

function LocationCard({
  location,
  onEdit,
  onDeactivate,
}: {
  location: WarehouseLocation;
  onEdit: () => void;
  onDeactivate: () => void;
}) {
  const addressParts = [
    location.address_street,
    location.address_city,
    [location.address_state, location.address_zip].filter(Boolean).join(' '),
  ].filter(Boolean);

  return (
    <div
      className={`bg-surface border rounded-xl p-4 ${
        !location.is_active
          ? 'border-border opacity-60'
          : location.is_primary
            ? 'border-blue-300 dark:border-blue-700'
            : 'border-border'
      }`}
    >
      {/* Header row */}
      <div className="flex items-start justify-between gap-2 mb-2">
        <div className="flex items-center gap-2 min-w-0">
          <div
            className={`flex items-center justify-center h-8 w-8 rounded-lg shrink-0 ${
              location.is_primary
                ? 'bg-blue-50 dark:bg-blue-900/20 text-blue-500 dark:text-blue-400'
                : 'bg-gray-100 dark:bg-gray-800 text-gray-400 dark:text-gray-500'
            }`}
          >
            {location.is_primary ? (
              <Star className="h-4 w-4" />
            ) : (
              <Building2 className="h-4 w-4" />
            )}
          </div>
          <div className="min-w-0">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
              {location.name}
            </h3>
            <div className="flex items-center gap-1.5 flex-wrap">
              {location.is_primary && (
                <Badge variant="info">Primary</Badge>
              )}
              {!location.is_active && (
                <Badge variant="default">Inactive</Badge>
              )}
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="flex items-center gap-1 shrink-0">
          <button
            onClick={onEdit}
            className="p-1.5 rounded-md text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors"
            title="Edit"
          >
            <Pencil className="h-3.5 w-3.5" />
          </button>
          {location.is_active && (
            <button
              onClick={onDeactivate}
              className="p-1.5 rounded-md text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
              title="Deactivate"
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
      </div>

      {/* Address */}
      {addressParts.length > 0 ? (
        <div className="flex items-start gap-2 mt-3">
          <MapPin className="h-4 w-4 text-gray-400 dark:text-gray-500 shrink-0 mt-0.5" />
          <div className="text-sm text-gray-600 dark:text-gray-300 leading-relaxed">
            {addressParts.map((line, i) => (
              <span key={i}>
                {line}
                {i < addressParts.length - 1 && <br />}
              </span>
            ))}
          </div>
        </div>
      ) : (
        <p className="text-sm text-gray-400 dark:text-gray-500 mt-3 italic">
          No address entered
        </p>
      )}

      {/* Phone */}
      {location.phone && (
        <div className="flex items-center gap-2 mt-2">
          <Phone className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500 shrink-0" />
          <span className="text-sm text-gray-500 dark:text-gray-400">{location.phone}</span>
        </div>
      )}

      {/* Notes */}
      {location.notes && (
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-2 line-clamp-2">
          {location.notes}
        </p>
      )}

      {/* GPS coords if present */}
      {location.gps_lat != null && location.gps_lng != null && (
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-2 font-mono">
          {location.gps_lat.toFixed(5)}, {location.gps_lng.toFixed(5)}
        </p>
      )}
    </div>
  );
}


// ── Location Form Modal ──────────────────────────────────────────

interface LocationFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  mode: 'create' | 'edit';
  location?: WarehouseLocation;
}

function LocationFormModal({ isOpen, onClose, mode, location }: LocationFormModalProps) {
  const queryClient = useQueryClient();

  const [name, setName] = useState(location?.name ?? '');
  const [street, setStreet] = useState(location?.address_street ?? '');
  const [city, setCity] = useState(location?.address_city ?? '');
  const [state, setState] = useState(location?.address_state ?? '');
  const [zip, setZip] = useState(location?.address_zip ?? '');
  const [phone, setPhone] = useState(location?.phone ?? '');
  const [isPrimary, setIsPrimary] = useState(location?.is_primary ?? false);
  const [isActive, setIsActive] = useState(location?.is_active ?? true);
  const [notes, setNotes] = useState(location?.notes ?? '');
  const [gpsLat, setGpsLat] = useState(location?.gps_lat?.toString() ?? '');
  const [gpsLng, setGpsLng] = useState(location?.gps_lng?.toString() ?? '');

  const createMut = useMutation({
    mutationFn: (data: WarehouseLocationCreate) => createWarehouseLocation(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['warehouse-locations'] });
      onClose();
    },
  });

  const updateMut = useMutation({
    mutationFn: ({ id, data }: { id: number; data: WarehouseLocationUpdate }) =>
      updateWarehouseLocation(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['warehouse-locations'] });
      onClose();
    },
  });

  const isSaving = createMut.isPending || updateMut.isPending;
  const mutError = createMut.error || updateMut.error;

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;

    const payload = {
      name: name.trim(),
      address_street: street.trim() || undefined,
      address_city: city.trim() || undefined,
      address_state: state.trim() || undefined,
      address_zip: zip.trim() || undefined,
      phone: phone.trim() || undefined,
      is_primary: isPrimary,
      notes: notes.trim() || undefined,
      gps_lat: gpsLat ? parseFloat(gpsLat) : undefined,
      gps_lng: gpsLng ? parseFloat(gpsLng) : undefined,
    };

    if (mode === 'create') {
      createMut.mutate(payload);
    } else if (location) {
      updateMut.mutate({
        id: location.id,
        data: { ...payload, is_active: isActive },
      });
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      size="lg"
      title={mode === 'create' ? 'Add Location' : 'Edit Location'}
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {mutError && (
          <p className="text-sm text-red-500">
            {(mutError as Error).message || 'Failed to save location.'}
          </p>
        )}

            {/* Name */}
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Location Name *
              </label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Main Shop"
                required
              />
            </div>

            {/* Address */}
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Street Address
              </label>
              <Input
                value={street}
                onChange={(e) => setStreet(e.target.value)}
                placeholder="123 Industrial Dr"
              />
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              <div className="col-span-2 sm:col-span-1">
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  City
                </label>
                <Input
                  value={city}
                  onChange={(e) => setCity(e.target.value)}
                  placeholder="Springfield"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  State
                </label>
                <Input
                  value={state}
                  onChange={(e) => setState(e.target.value)}
                  placeholder="IL"
                  maxLength={2}
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  ZIP
                </label>
                <Input
                  value={zip}
                  onChange={(e) => setZip(e.target.value)}
                  placeholder="62704"
                  maxLength={10}
                />
              </div>
            </div>

            {/* Phone */}
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Phone
              </label>
              <Input
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="(555) 123-4567"
              />
            </div>

            {/* GPS coordinates (optional) */}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  GPS Latitude
                </label>
                <Input
                  value={gpsLat}
                  onChange={(e) => setGpsLat(e.target.value)}
                  placeholder="39.7817"
                  type="number"
                  step="any"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  GPS Longitude
                </label>
                <Input
                  value={gpsLng}
                  onChange={(e) => setGpsLng(e.target.value)}
                  placeholder="-89.6501"
                  type="number"
                  step="any"
                />
              </div>
            </div>

            {/* Flags */}
            <div className="flex flex-wrap gap-4">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={isPrimary}
                  onChange={(e) => setIsPrimary(e.target.checked)}
                  className="rounded border-gray-300 dark:border-gray-600"
                />
                <span className="text-sm text-gray-700 dark:text-gray-300">Primary location</span>
              </label>
              {mode === 'edit' && (
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={isActive}
                    onChange={(e) => setIsActive(e.target.checked)}
                    className="rounded border-gray-300 dark:border-gray-600"
                  />
                  <span className="text-sm text-gray-700 dark:text-gray-300">Active</span>
                </label>
              )}
            </div>

            {/* Notes */}
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Notes
              </label>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={2}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
                placeholder="Gate code, parking instructions, etc."
              />
            </div>

          {/* Footer buttons */}
          <div className="flex items-center justify-end gap-2 pt-4 border-t border-gray-200 dark:border-gray-700">
            <Button type="button" variant="secondary" onClick={onClose} disabled={isSaving}>
              Cancel
            </Button>
            <Button type="submit" disabled={!name.trim() || isSaving}>
              {isSaving ? 'Saving...' : mode === 'create' ? 'Create' : 'Save Changes'}
            </Button>
          </div>
      </form>
    </Modal>
  );
}
