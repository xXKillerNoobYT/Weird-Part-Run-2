"""
Pydantic models for the Fleet & Vehicle Management system.

Covers:
  - Vehicles — company trucks, vans, cars, and private employee vehicles
  - Vehicle Assignments — driver-to-vehicle mappings with take-home support
  - Warehouse Locations — physical shop/warehouse addresses
  - Vehicle Delivery Items — job-bound parts on a truck
  - Maintenance Types — configurable service categories
  - Maintenance Schedules — per-vehicle interval overrides
  - Maintenance Records — service history entries
  - Mileage Logs — daily odometer readings
  - Trip Legs — individual trip segments with drive time
  - Mileage Reimbursements — private vehicle payback
  - Dashboard aggregation models
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════
# Vehicle Models
# ═══════════════════════════════════════════════════════════════

class VehicleCreate(BaseModel):
    """Create a new vehicle."""
    vehicle_number: str = Field(..., min_length=1, max_length=20)
    vehicle_name: str | None = Field(None, max_length=100)
    vehicle_type: str = "company_truck"  # company_truck | company_van | company_car | private_vehicle
    make: str | None = None
    model: str | None = None
    year: int | None = None
    color: str | None = None
    vin: str | None = None
    license_plate: str | None = None
    insurance_policy: str | None = None
    insurance_expiry: str | None = None
    registration_expiry: str | None = None
    current_odometer: int = 0
    owner_user_id: int | None = None  # required for private_vehicle
    notes: str | None = None


class VehicleUpdate(BaseModel):
    """Update an existing vehicle."""
    vehicle_name: str | None = Field(None, min_length=1, max_length=100)
    vehicle_type: str | None = None
    status: str | None = None
    make: str | None = None
    model: str | None = None
    year: int | None = None
    color: str | None = None
    vin: str | None = None
    license_plate: str | None = None
    insurance_policy: str | None = None
    insurance_expiry: str | None = None
    registration_expiry: str | None = None
    current_odometer: int | None = None
    notes: str | None = None
    photo_path: str | None = None


class VehicleResponse(BaseModel):
    """Full vehicle detail in API responses."""
    id: int
    vehicle_number: str
    vehicle_name: str
    vehicle_type: str
    status: str = "active"
    make: str | None = None
    model: str | None = None
    year: int | None = None
    color: str | None = None
    vin: str | None = None
    license_plate: str | None = None
    insurance_policy: str | None = None
    insurance_expiry: str | None = None
    registration_expiry: str | None = None
    current_odometer: int = 0
    owner_user_id: int | None = None
    notes: str | None = None
    photo_path: str | None = None
    is_active: bool = True
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    owner_name: str | None = None
    primary_driver_name: str | None = None
    primary_driver_id: int | None = None
    assignment_count: int = 0
    next_maintenance_due: str | None = None
    next_maintenance_type: str | None = None


class VehicleListItem(BaseModel):
    """Compact vehicle for list views."""
    id: int
    vehicle_number: str
    vehicle_name: str
    vehicle_type: str
    status: str = "active"
    make: str | None = None
    model: str | None = None
    year: int | None = None
    license_plate: str | None = None
    current_odometer: int = 0
    is_active: bool = True
    created_at: datetime | None = None
    # Joined fields
    primary_driver_name: str | None = None
    primary_driver_id: int | None = None
    next_maintenance_due: str | None = None
    overdue_maintenance_count: int = 0


# ═══════════════════════════════════════════════════════════════
# Vehicle Assignment Models
# ═══════════════════════════════════════════════════════════════

class VehicleAssignmentCreate(BaseModel):
    """Assign a driver to a vehicle."""
    user_id: int
    assignment_type: str = "primary"  # primary | authorized | temporary
    is_take_home: bool = False
    home_to_shop_miles: float | None = None
    home_address_street: str | None = None
    home_address_city: str | None = None
    home_address_state: str | None = None
    home_address_zip: str | None = None
    notes: str | None = None


class VehicleAssignmentUpdate(BaseModel):
    """Update an assignment."""
    assignment_type: str | None = None
    is_take_home: bool | None = None
    home_to_shop_miles: float | None = None
    home_address_street: str | None = None
    home_address_city: str | None = None
    home_address_state: str | None = None
    home_address_zip: str | None = None
    notes: str | None = None


class VehicleAssignmentResponse(BaseModel):
    """Assignment in API responses."""
    id: int
    vehicle_id: int
    user_id: int
    assignment_type: str = "primary"
    is_take_home: bool = False
    home_to_shop_miles: float | None = None
    home_address_street: str | None = None
    home_address_city: str | None = None
    home_address_state: str | None = None
    home_address_zip: str | None = None
    start_date: str | None = None
    end_date: str | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    user_name: str | None = None
    vehicle_name: str | None = None
    vehicle_number: str | None = None


# ═══════════════════════════════════════════════════════════════
# Warehouse Location Models
# ═══════════════════════════════════════════════════════════════

class WarehouseLocationCreate(BaseModel):
    """Create a new warehouse/shop location."""
    name: str = Field(..., min_length=1, max_length=100)
    address_street: str | None = None
    address_city: str | None = None
    address_state: str | None = None
    address_zip: str | None = None
    gps_lat: float | None = None
    gps_lng: float | None = None
    is_primary: bool = False
    company_profile_id: int | None = None
    phone: str | None = None
    notes: str | None = None


class WarehouseLocationUpdate(BaseModel):
    """Update a warehouse/shop location."""
    name: str | None = Field(None, min_length=1, max_length=100)
    address_street: str | None = None
    address_city: str | None = None
    address_state: str | None = None
    address_zip: str | None = None
    gps_lat: float | None = None
    gps_lng: float | None = None
    is_primary: bool | None = None
    company_profile_id: int | None = None
    phone: str | None = None
    is_active: bool | None = None
    notes: str | None = None


class WarehouseLocationResponse(BaseModel):
    """Warehouse location in API responses."""
    id: int
    name: str
    address_street: str | None = None
    address_city: str | None = None
    address_state: str | None = None
    address_zip: str | None = None
    gps_lat: float | None = None
    gps_lng: float | None = None
    is_primary: bool = False
    is_active: bool = True
    company_profile_id: int | None = None
    phone: str | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ═══════════════════════════════════════════════════════════════
# Job Trailer Models
# ═══════════════════════════════════════════════════════════════

class JobTrailerCreate(BaseModel):
    """Create a new job trailer."""
    trailer_code: str = Field(..., min_length=1, max_length=30)
    name: str = Field(..., min_length=1, max_length=100)
    status: str = "active"
    home_warehouse_id: int | None = None
    current_job_id: int | None = None
    assigned_driver_user_id: int | None = None
    notes: str | None = None


class JobTrailerUpdate(BaseModel):
    """Update an existing job trailer."""
    name: str | None = Field(None, min_length=1, max_length=100)
    status: str | None = None
    home_warehouse_id: int | None = None
    current_job_id: int | None = None
    assigned_driver_user_id: int | None = None
    notes: str | None = None
    is_active: bool | None = None


class JobTrailerResponse(BaseModel):
    """Trailer detail in API responses."""
    id: int
    trailer_code: str
    name: str
    status: str = "active"
    home_warehouse_id: int | None = None
    current_job_id: int | None = None
    assigned_driver_user_id: int | None = None
    notes: str | None = None
    is_active: bool = True
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # joined fields
    home_warehouse_name: str | None = None
    current_job_name: str | None = None
    assigned_driver_name: str | None = None


class TrailerLocationEventCreate(BaseModel):
    """Create a trailer location event."""
    event_type: str = "manual_update"
    location_kind: str = "other"  # warehouse | job | road | other
    warehouse_id: int | None = None
    job_id: int | None = None
    lat: float | None = None
    lng: float | None = None
    notes: str | None = None


class TrailerLocationEventResponse(BaseModel):
    """Trailer location event payload."""
    id: int
    trailer_id: int
    event_type: str
    location_kind: str
    warehouse_id: int | None = None
    job_id: int | None = None
    lat: float | None = None
    lng: float | None = None
    recorded_by: int
    recorded_at: datetime | None = None
    notes: str | None = None
    # joined fields
    recorded_by_name: str | None = None
    warehouse_name: str | None = None
    job_name: str | None = None


# ═══════════════════════════════════════════════════════════════
# Vehicle Delivery Item Models
# ═══════════════════════════════════════════════════════════════

class DeliveryItemCreate(BaseModel):
    """Assign parts for delivery on a vehicle to a job."""
    job_id: int
    part_id: int
    qty_assigned: int = Field(1, ge=1)
    notes: str | None = None


class DeliveryItemBulkCreate(BaseModel):
    """Assign multiple parts for delivery at once."""
    job_id: int
    items: list[DeliveryItemCreate]


class DeliveryItemUpdate(BaseModel):
    """Update a delivery item (e.g. partial delivery)."""
    qty_delivered: int | None = None
    status: str | None = None
    notes: str | None = None


class DeliveryItemResponse(BaseModel):
    """Delivery item in API responses."""
    id: int
    vehicle_id: int
    job_id: int
    part_id: int
    qty_assigned: int = 1
    qty_delivered: int = 0
    assigned_by: int | None = None
    delivered_by: int | None = None
    delivered_at: datetime | None = None
    status: str = "assigned"
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    job_name: str | None = None
    part_number: str | None = None
    part_description: str | None = None
    assigner_name: str | None = None


# ═══════════════════════════════════════════════════════════════
# Maintenance Type Models
# ═══════════════════════════════════════════════════════════════

class MaintenanceTypeCreate(BaseModel):
    """Create a new maintenance type."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    default_interval_miles: int | None = None
    default_interval_months: int | None = None
    sort_order: int = 0


class MaintenanceTypeUpdate(BaseModel):
    """Update a maintenance type."""
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    default_interval_miles: int | None = None
    default_interval_months: int | None = None
    sort_order: int | None = None
    is_active: bool | None = None


class MaintenanceTypeResponse(BaseModel):
    """Maintenance type in API responses."""
    id: int
    name: str
    description: str | None = None
    default_interval_miles: int | None = None
    default_interval_months: int | None = None
    sort_order: int = 0
    is_active: bool = True
    created_at: datetime | None = None


# ═══════════════════════════════════════════════════════════════
# Maintenance Schedule Models
# ═══════════════════════════════════════════════════════════════

class MaintenanceScheduleCreate(BaseModel):
    """Set or update a maintenance schedule for a vehicle."""
    maintenance_type_id: int
    interval_miles: int | None = None    # override type default
    interval_months: int | None = None   # override type default
    last_performed_at: str | None = None
    last_performed_miles: int | None = None
    is_enabled: bool = True
    notes: str | None = None


class MaintenanceScheduleUpdate(BaseModel):
    """Update a maintenance schedule entry."""
    interval_miles: int | None = None
    interval_months: int | None = None
    last_performed_at: str | None = None
    last_performed_miles: int | None = None
    next_due_date: str | None = None
    next_due_miles: int | None = None
    is_enabled: bool | None = None
    notes: str | None = None


class MaintenanceScheduleResponse(BaseModel):
    """Maintenance schedule in API responses."""
    id: int
    vehicle_id: int
    maintenance_type_id: int
    interval_miles: int | None = None
    interval_months: int | None = None
    last_performed_at: str | None = None
    last_performed_miles: int | None = None
    next_due_date: str | None = None
    next_due_miles: int | None = None
    is_enabled: bool = True
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    maintenance_type_name: str | None = None
    vehicle_name: str | None = None
    vehicle_number: str | None = None
    current_odometer: int | None = None


# ═══════════════════════════════════════════════════════════════
# Maintenance Record Models
# ═══════════════════════════════════════════════════════════════

class MaintenanceRecordCreate(BaseModel):
    """Log a new maintenance service."""
    maintenance_type_id: int
    service_date: str | None = None  # defaults to today
    odometer_reading: int | None = None
    cost: float = 0
    vendor: str | None = None
    invoice_number: str | None = None
    description: str | None = None
    photo_path: str | None = None
    notes: str | None = None


class MaintenanceRecordResponse(BaseModel):
    """Maintenance record in API responses."""
    id: int
    vehicle_id: int
    maintenance_type_id: int
    service_date: str
    odometer_reading: int | None = None
    cost: float = 0
    vendor: str | None = None
    invoice_number: str | None = None
    description: str | None = None
    performed_by: int | None = None
    photo_path: str | None = None
    notes: str | None = None
    created_at: datetime | None = None
    # Joined fields
    maintenance_type_name: str | None = None
    performer_name: str | None = None
    vehicle_name: str | None = None


# ═══════════════════════════════════════════════════════════════
# Mileage Log Models
# ═══════════════════════════════════════════════════════════════

class MileageLogCreate(BaseModel):
    """Log daily mileage for a vehicle."""
    log_date: str | None = None  # defaults to today
    odometer_start: int | None = None
    odometer_end: int | None = None
    is_take_home_day: bool = False
    notes: str | None = None


class MileageLogUpdate(BaseModel):
    """Update a mileage log entry."""
    odometer_start: int | None = None
    odometer_end: int | None = None
    is_take_home_day: bool | None = None
    notes: str | None = None


class MileageLogResponse(BaseModel):
    """Mileage log in API responses."""
    id: int
    vehicle_id: int
    driver_id: int
    log_date: str
    odometer_start: int | None = None
    odometer_end: int | None = None
    total_miles: int | None = None  # generated column
    is_take_home_day: bool = False
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    driver_name: str | None = None
    vehicle_name: str | None = None
    vehicle_number: str | None = None
    trip_legs: list[TripLegResponse] | None = None


# ═══════════════════════════════════════════════════════════════
# Trip Leg Models
# ═══════════════════════════════════════════════════════════════

class TripLegCreate(BaseModel):
    """Add a trip segment to a mileage log."""
    leg_order: int = 1
    leg_type: str  # home_to_shop | shop_to_job | job_to_job | job_to_shop | shop_to_home | job_to_home | other
    from_label: str | None = None
    to_label: str | None = None
    estimated_miles: float | None = None
    actual_miles: float | None = None
    estimated_drive_minutes: int | None = None
    actual_drive_minutes: int | None = None
    is_billable: bool = False
    from_job_id: int | None = None
    to_job_id: int | None = None
    notes: str | None = None


class TripLegResponse(BaseModel):
    """Trip leg in API responses."""
    id: int
    mileage_log_id: int
    leg_order: int = 1
    leg_type: str
    from_label: str | None = None
    to_label: str | None = None
    estimated_miles: float | None = None
    actual_miles: float | None = None
    estimated_drive_minutes: int | None = None
    actual_drive_minutes: int | None = None
    is_billable: bool = False
    from_job_id: int | None = None
    to_job_id: int | None = None
    notes: str | None = None
    created_at: datetime | None = None
    # Joined fields
    from_job_name: str | None = None
    to_job_name: str | None = None


class TripLegBulkCreate(BaseModel):
    """Add multiple trip legs at once."""
    legs: list[TripLegCreate]


# ═══════════════════════════════════════════════════════════════
# Mileage Reimbursement Models
# ═══════════════════════════════════════════════════════════════

class ReimbursementCreate(BaseModel):
    """Create a reimbursement for a period."""
    vehicle_id: int
    period_start: str
    period_end: str
    total_miles: int = Field(..., ge=0)
    rate_per_mile: float | None = None  # uses system default if not set
    notes: str | None = None


class ReimbursementResponse(BaseModel):
    """Reimbursement in API responses."""
    id: int
    user_id: int
    vehicle_id: int
    period_start: str
    period_end: str
    total_miles: int = 0
    rate_per_mile: float = 0.70
    total_amount: float | None = None  # generated column
    status: str = "pending"
    approved_by: int | None = None
    approved_at: datetime | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    user_name: str | None = None
    vehicle_name: str | None = None
    approver_name: str | None = None


class ReimbursementApproval(BaseModel):
    """Approve or reject a reimbursement."""
    action: str = Field(..., pattern="^(approve|reject)$")
    notes: str | None = None


# ═══════════════════════════════════════════════════════════════
# Dashboard / Aggregation Models
# ═══════════════════════════════════════════════════════════════

class FleetDashboardStats(BaseModel):
    """Summary stats for the fleet dashboard."""
    total_vehicles: int = 0
    active_vehicles: int = 0
    in_maintenance: int = 0
    retired_vehicles: int = 0
    company_vehicles: int = 0
    private_vehicles: int = 0
    total_fleet_miles_month: int = 0
    total_maintenance_cost_month: float = 0
    overdue_maintenance_count: int = 0
    upcoming_maintenance_count: int = 0
    pending_reimbursements: int = 0
    vehicles_needing_inspection: int = 0


class MyVehicleDashboard(BaseModel):
    """Driver's personal vehicle dashboard bundle."""
    vehicle: VehicleResponse | None = None
    assignment: VehicleAssignmentResponse | None = None
    todays_mileage: MileageLogResponse | None = None
    pending_deliveries: list[DeliveryItemResponse] = Field(default_factory=list)
    maintenance_alerts: list[MaintenanceAlert] = Field(default_factory=list)
    recent_mileage: list[MileageLogResponse] = Field(default_factory=list)


class MaintenanceAlert(BaseModel):
    """An upcoming or overdue maintenance item."""
    vehicle_id: int
    vehicle_name: str
    vehicle_number: str
    maintenance_type_id: int
    maintenance_type_name: str
    next_due_date: str | None = None
    next_due_miles: int | None = None
    current_odometer: int = 0
    miles_until_due: int | None = None
    days_until_due: int | None = None
    is_overdue: bool = False
    urgency: str = "normal"  # normal | soon | overdue


class MileageEstimate(BaseModel):
    """Calculated trip distance and drive time estimate."""
    home_to_shop_miles: float | None = None
    shop_to_job_miles: float | None = None
    total_round_trip_miles: float | None = None
    total_billable_miles: float | None = None
    estimated_drive_minutes_one_way: int | None = None
    estimated_billable_drive_minutes: int | None = None
    is_take_home: bool = False
    legs: list[MileageEstimateLeg] = Field(default_factory=list)


class MileageEstimateLeg(BaseModel):
    """A single leg in a mileage estimate."""
    leg_type: str
    from_label: str
    to_label: str
    estimated_miles: float
    estimated_drive_minutes: int | None = None
    is_billable: bool = False


class MileageSummary(BaseModel):
    """Aggregated mileage stats for a period."""
    vehicle_id: int | None = None
    driver_id: int | None = None
    period_start: str
    period_end: str
    total_miles: int = 0
    total_days_logged: int = 0
    total_billable_drive_minutes: int = 0
    avg_miles_per_day: float = 0
    total_take_home_days: int = 0
