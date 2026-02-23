"""
Parts, Brands, Suppliers, Hierarchy, and Stock Pydantic models.

Covers all request/response schemas for Phase 2: Parts & Inventory Core.
Organized into sections: Hierarchy, Brands, Brand-Supplier Links, Suppliers,
Parts (Variants), Part-Supplier Links, Stock, Movements, Search Params.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, model_validator


# =================================================================
# PART HIERARCHY (Category → Style → Type → Color)
# =================================================================

# ── Categories ──────────────────────────────────────────────────

class PartCategoryCreate(BaseModel):
    """Request body for creating a new part category."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    sort_order: int = 0
    image_url: str | None = None


class PartCategoryUpdate(BaseModel):
    """Request body for updating a category. All fields optional."""
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    sort_order: int | None = None
    is_active: bool | None = None
    image_url: str | None = None


class PartCategoryResponse(BaseModel):
    """A part category as returned from the API."""
    id: int
    name: str
    description: str | None = None
    sort_order: int = 0
    is_active: bool = True
    image_url: str | None = None
    style_count: int = 0    # Computed: number of child styles
    part_count: int = 0     # Computed: number of parts in this category
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── Styles ──────────────────────────────────────────────────────

class PartStyleCreate(BaseModel):
    """Request body for creating a new style under a category."""
    category_id: int
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    sort_order: int = 0
    image_url: str | None = None


class PartStyleUpdate(BaseModel):
    """Request body for updating a style. All fields optional."""
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    sort_order: int | None = None
    is_active: bool | None = None
    image_url: str | None = None


class PartStyleResponse(BaseModel):
    """A part style as returned from the API."""
    id: int
    category_id: int
    category_name: str | None = None
    name: str
    description: str | None = None
    sort_order: int = 0
    is_active: bool = True
    image_url: str | None = None
    type_count: int = 0     # Computed: number of child types
    part_count: int = 0     # Computed: number of parts with this style
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── Types ───────────────────────────────────────────────────────

class PartTypeCreate(BaseModel):
    """Request body for creating a new type under a style."""
    style_id: int
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    sort_order: int = 0
    image_url: str | None = None


class PartTypeUpdate(BaseModel):
    """Request body for updating a type. All fields optional."""
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    sort_order: int | None = None
    is_active: bool | None = None
    image_url: str | None = None


class PartTypeResponse(BaseModel):
    """A part type as returned from the API."""
    id: int
    style_id: int
    style_name: str | None = None
    category_name: str | None = None
    name: str
    description: str | None = None
    sort_order: int = 0
    is_active: bool = True
    image_url: str | None = None
    color_count: int = 0    # Computed: number of linked colors
    part_count: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── Colors ──────────────────────────────────────────────────────

class PartColorCreate(BaseModel):
    """Request body for creating a new color."""
    name: str = Field(..., min_length=1, max_length=50)
    hex_code: str | None = Field(None, pattern=r"^#[0-9A-Fa-f]{6}$")
    sort_order: int = 0


class PartColorUpdate(BaseModel):
    """Request body for updating a color. All fields optional."""
    name: str | None = Field(None, min_length=1, max_length=50)
    hex_code: str | None = None
    sort_order: int | None = None
    is_active: bool | None = None


class PartColorResponse(BaseModel):
    """A color as returned from the API."""
    id: int
    name: str
    hex_code: str | None = None
    sort_order: int = 0
    is_active: bool = True
    part_count: int = 0
    created_at: datetime | None = None


# ── Type ↔ Color Links ─────────────────────────────────────────────

class TypeColorLinkCreate(BaseModel):
    """Request body for linking a color to a type."""
    type_id: int
    color_id: int
    image_url: str | None = None
    sort_order: int = 0


class TypeColorLinkResponse(BaseModel):
    """A type-color link as returned from the API."""
    id: int
    type_id: int
    color_id: int
    color_name: str | None = None
    hex_code: str | None = None
    image_url: str | None = None
    sort_order: int = 0
    created_at: datetime | None = None


# ── Type ↔ Brand Links ─────────────────────────────────────────────

class TypeBrandLinkCreate(BaseModel):
    """Request body for linking a brand (or General) to a type."""
    type_id: int
    brand_id: int | None = None  # None = General (unbranded)


class TypeBrandLinkResponse(BaseModel):
    """A type-brand link as returned from the API."""
    id: int
    type_id: int
    brand_id: int | None = None       # None = General
    brand_name: str | None = None     # "General" when brand_id is None
    part_count: int = 0               # How many Part records exist under this link
    created_at: datetime | None = None


class QuickCreatePartRequest(BaseModel):
    """Minimal request body for creating a part from the Categories tree.

    The hierarchy context (category, style, type, brand) is inferred from the
    URL path. Only the color_id is needed from the user.
    """
    color_id: int


# ── Hierarchy Tree (nested response for UI dropdowns) ───────────

class HierarchyTypeColor(BaseModel):
    """A color linked to a specific type (valid combo)."""
    id: int             # type_color_link.id
    color_id: int
    name: str
    hex_code: str | None = None
    image_url: str | None = None
    sort_order: int = 0


class HierarchyType(BaseModel):
    """A type within a style, with its valid colors."""
    id: int
    name: str
    image_url: str | None = None
    sort_order: int = 0
    colors: list[HierarchyTypeColor] = Field(default_factory=list)


class HierarchyStyle(BaseModel):
    """A style within a category, with its child types."""
    id: int
    name: str
    image_url: str | None = None
    sort_order: int = 0
    types: list[HierarchyType] = Field(default_factory=list)


class HierarchyCategory(BaseModel):
    """A category with its child styles."""
    id: int
    name: str
    image_url: str | None = None
    sort_order: int = 0
    styles: list[HierarchyStyle] = Field(default_factory=list)


class HierarchyColor(BaseModel):
    """A color in the hierarchy response (global master list)."""
    id: int
    name: str
    hex_code: str | None = None
    image_url: str | None = None
    sort_order: int = 0


class HierarchyTree(BaseModel):
    """The full hierarchy tree for powering UI cascading dropdowns.

    categories: nested tree (category → style → type → linked colors)
    colors: flat master list (all colors for the global color editor)
    """
    categories: list[HierarchyCategory] = Field(default_factory=list)
    colors: list[HierarchyColor] = Field(default_factory=list)


# ── Catalog Groups (grouped product card view) ────────────────────

class CatalogGroupVariant(BaseModel):
    """A single part variant within a catalog group."""
    id: int
    style_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    code: str | None = None
    name: str
    manufacturer_part_number: str | None = None
    has_pending_part_number: bool = False
    unit_of_measure: str = "each"
    company_cost_price: float | None = None
    company_sell_price: float | None = None
    total_stock: int = 0
    image_url: str | None = None
    is_deprecated: bool = False


class CatalogGroup(BaseModel):
    """A group of parts sharing the same category + brand.

    The grouping key is (category_id, brand_id) where brand_id=NULL → "General".
    Each group becomes one product card in the catalog UI.
    """
    category_id: int
    category_name: str
    brand_id: int | None = None
    brand_name: str | None = None
    image_url: str | None = None       # Resolved cascade image for this group
    variant_count: int = 0
    total_stock: int = 0
    price_range_low: float | None = None
    price_range_high: float | None = None
    variants: list[CatalogGroupVariant] = Field(default_factory=list)


# =================================================================
# BRANDS
# =================================================================

class BrandCreate(BaseModel):
    """Request body for creating a new brand."""
    name: str = Field(..., min_length=1, max_length=100)
    website: str | None = None
    notes: str | None = None


class BrandUpdate(BaseModel):
    """Request body for updating an existing brand. All fields optional."""
    name: str | None = Field(None, min_length=1, max_length=100)
    website: str | None = None
    notes: str | None = None
    is_active: bool | None = None


class BrandResponse(BaseModel):
    """A brand as returned from the API."""
    id: int
    name: str
    website: str | None = None
    notes: str | None = None
    is_active: bool = True
    part_count: int = 0       # Number of parts using this brand
    supplier_count: int = 0   # Number of suppliers carrying this brand
    created_at: datetime | None = None
    updated_at: datetime | None = None


# =================================================================
# BRAND ↔ SUPPLIER LINKS
# =================================================================

class BrandSupplierLinkCreate(BaseModel):
    """Request body for linking a brand to a supplier."""
    brand_id: int
    supplier_id: int
    account_number: str | None = None
    notes: str | None = None


class BrandSupplierLinkResponse(BaseModel):
    """A brand-supplier link as returned from the API."""
    id: int
    brand_id: int
    brand_name: str | None = None
    supplier_id: int
    supplier_name: str | None = None
    account_number: str | None = None
    notes: str | None = None
    is_active: bool = True
    created_at: datetime | None = None


# =================================================================
# SUPPLIERS
# =================================================================

VALID_DELIVERY_METHODS = {"standard_shipping", "scheduled_delivery", "in_store_pickup"}


class SupplierCreate(BaseModel):
    """Request body for creating a new supplier."""
    name: str = Field(..., min_length=1, max_length=200)
    # Business contact (main office / general inquiries)
    contact_name: str | None = None
    email: str | None = None
    phone: str | None = None
    address: str | None = None
    website: str | None = None
    # Sales rep contact (the person you call for orders)
    rep_name: str | None = None
    rep_email: str | None = None
    rep_phone: str | None = None
    notes: str | None = None
    # Delivery logistics — multi-select with a primary
    delivery_methods: list[str] = Field(
        default=["standard_shipping"],
        description="All delivery methods this supplier offers",
    )
    primary_delivery_method: str = Field(
        default="standard_shipping",
        pattern=r"^(standard_shipping|scheduled_delivery|in_store_pickup)$",
        description="The default/preferred delivery method",
    )
    delivery_days: str | None = None  # JSON array: '["monday","wednesday"]'
    special_order_lead_days: int | None = Field(None, ge=0)
    delivery_notes: str | None = None
    # Delivery driver contact (the person physically bringing parts)
    driver_name: str | None = None
    driver_phone: str | None = None
    driver_email: str | None = None

    @model_validator(mode="after")
    def validate_delivery(self) -> "SupplierCreate":
        """Ensure all delivery methods are valid and primary is in the list."""
        for m in self.delivery_methods:
            if m not in VALID_DELIVERY_METHODS:
                raise ValueError(f"Invalid delivery method: {m}")
        if self.primary_delivery_method not in self.delivery_methods:
            # Auto-add primary to list if not present
            self.delivery_methods.append(self.primary_delivery_method)
        return self


class SupplierUpdate(BaseModel):
    """Request body for updating a supplier. All fields optional."""
    name: str | None = Field(None, min_length=1, max_length=200)
    # Business contact
    contact_name: str | None = None
    email: str | None = None
    phone: str | None = None
    address: str | None = None
    website: str | None = None
    # Sales rep contact
    rep_name: str | None = None
    rep_email: str | None = None
    rep_phone: str | None = None
    notes: str | None = None
    # Delivery logistics — multi-select with a primary
    delivery_methods: list[str] | None = None
    primary_delivery_method: str | None = Field(
        None,
        pattern=r"^(standard_shipping|scheduled_delivery|in_store_pickup)$",
    )
    delivery_days: str | None = None
    special_order_lead_days: int | None = Field(None, ge=0)
    delivery_notes: str | None = None
    # Delivery driver contact
    driver_name: str | None = None
    driver_phone: str | None = None
    driver_email: str | None = None
    # Reliability
    on_time_rate: float | None = Field(None, ge=0, le=1)
    quality_score: float | None = Field(None, ge=0, le=1)
    avg_lead_days: int | None = Field(None, ge=0)
    is_active: bool | None = None

    @model_validator(mode="after")
    def validate_delivery(self) -> "SupplierUpdate":
        """Ensure delivery methods are valid when provided."""
        if self.delivery_methods is not None:
            for m in self.delivery_methods:
                if m not in VALID_DELIVERY_METHODS:
                    raise ValueError(f"Invalid delivery method: {m}")
            if self.primary_delivery_method and self.primary_delivery_method not in self.delivery_methods:
                self.delivery_methods.append(self.primary_delivery_method)
        return self


class SupplierResponse(BaseModel):
    """A supplier as returned from the API."""
    id: int
    name: str
    # Business contact
    contact_name: str | None = None
    email: str | None = None
    phone: str | None = None
    address: str | None = None
    website: str | None = None
    # Sales rep contact
    rep_name: str | None = None
    rep_email: str | None = None
    rep_phone: str | None = None
    notes: str | None = None
    # Delivery logistics — multi-select with a primary
    delivery_methods: list[str] = Field(default=["standard_shipping"])
    primary_delivery_method: str = "standard_shipping"
    delivery_days: str | None = None
    special_order_lead_days: int | None = None
    delivery_notes: str | None = None
    # Delivery driver contact
    driver_name: str | None = None
    driver_phone: str | None = None
    driver_email: str | None = None
    # Reliability
    on_time_rate: float = 0.95
    quality_score: float = 0.90
    avg_lead_days: int = 5
    reliability_score: float = 0.85
    is_active: bool = True
    # Computed
    brand_count: int = 0    # Number of brands this supplier carries
    created_at: datetime | None = None
    updated_at: datetime | None = None


# =================================================================
# PART ↔ SUPPLIER LINKS
# =================================================================

class PartSupplierLinkCreate(BaseModel):
    """Link a supplier to a part with pricing/MOQ info."""
    supplier_id: int
    supplier_part_number: str | None = None
    supplier_cost_price: float | None = None
    moq: int = 1
    discount_brackets: str | None = None  # JSON string
    is_preferred: bool = False


class PartSupplierLinkResponse(BaseModel):
    """A part-supplier link with supplier details."""
    id: int
    supplier_id: int
    supplier_name: str | None = None
    supplier_part_number: str | None = None
    supplier_cost_price: float | None = None
    moq: int = 1
    discount_brackets: str | None = None
    is_preferred: bool = False
    last_price_date: str | None = None


# =================================================================
# PARTS (Orderable Variants)
# =================================================================

class PartCreate(BaseModel):
    """Request body for creating a new part variant."""
    # Hierarchy position (category required, rest optional)
    category_id: int
    style_id: int | None = None
    type_id: int | None = None
    color_id: int | None = None

    # Identity
    part_type: str = Field(default="general", pattern=r"^(general|specific)$")
    code: str | None = Field(None, min_length=1, max_length=50)  # Optional for general parts
    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = None

    # Brand (required for specific, ignored for general)
    brand_id: int | None = None
    manufacturer_part_number: str | None = None  # Can be NULL = "pending" for specific

    # Physical
    unit_of_measure: str = "each"
    weight_lbs: float | None = None

    # Pricing
    company_cost_price: float = Field(default=0.0, ge=0)
    company_markup_percent: float = Field(default=0.0, ge=0)

    # Inventory targets
    min_stock_level: int = Field(default=0, ge=0)
    max_stock_level: int = Field(default=0, ge=0)
    target_stock_level: int = Field(default=0, ge=0)

    # Metadata
    notes: str | None = None
    image_url: str | None = None
    pdf_url: str | None = None


class PartUpdate(BaseModel):
    """Request body for updating a part. All fields optional."""
    # Hierarchy position
    category_id: int | None = None
    style_id: int | None = None
    type_id: int | None = None
    color_id: int | None = None

    # Identity
    part_type: str | None = Field(None, pattern=r"^(general|specific)$")
    code: str | None = Field(None, min_length=1, max_length=50)
    name: str | None = Field(None, min_length=1, max_length=200)
    description: str | None = None

    # Brand
    brand_id: int | None = None
    manufacturer_part_number: str | None = None

    # Physical
    unit_of_measure: str | None = None
    weight_lbs: float | None = None

    # Pricing
    company_cost_price: float | None = Field(None, ge=0)
    company_markup_percent: float | None = Field(None, ge=0)

    # Inventory targets
    min_stock_level: int | None = Field(None, ge=0)
    max_stock_level: int | None = Field(None, ge=0)
    target_stock_level: int | None = Field(None, ge=0)

    # Status
    is_deprecated: bool | None = None
    deprecation_reason: str | None = None
    is_qr_tagged: bool | None = None
    notes: str | None = None
    image_url: str | None = None
    pdf_url: str | None = None


class PartPricingUpdate(BaseModel):
    """Update only the pricing fields (requires edit_pricing permission)."""
    company_cost_price: float = Field(..., ge=0)
    company_markup_percent: float = Field(..., ge=0)


class PartResponse(BaseModel):
    """A part as returned from the API (full detail)."""
    id: int

    # Hierarchy
    category_id: int
    category_name: str | None = None
    style_id: int | None = None
    style_name: str | None = None
    type_id: int | None = None
    type_name: str | None = None
    color_id: int | None = None
    color_name: str | None = None
    color_hex: str | None = None

    # Identity
    part_type: str = "general"
    code: str | None = None
    name: str
    description: str | None = None

    # Brand
    brand_id: int | None = None
    brand_name: str | None = None
    manufacturer_part_number: str | None = None
    has_pending_part_number: bool = False  # Computed: specific + no MPN

    # Physical
    unit_of_measure: str = "each"
    weight_lbs: float | None = None

    # Pricing (only populated if user has show_dollar_values permission)
    company_cost_price: float | None = None
    company_markup_percent: float | None = None
    company_sell_price: float | None = None

    # Inventory targets
    min_stock_level: int = 0
    max_stock_level: int = 0
    target_stock_level: int = 0

    # Computed stock totals (from stock table aggregation)
    total_stock: int = 0
    warehouse_stock: int = 0
    truck_stock: int = 0
    job_stock: int = 0
    pulled_stock: int = 0

    # Forecasting
    forecast_adu_30: float | None = None
    forecast_days_until_low: int | None = None
    forecast_suggested_order: int | None = None
    forecast_last_run: str | None = None

    # Status
    is_deprecated: bool = False
    deprecation_reason: str | None = None
    is_qr_tagged: bool = False
    notes: str | None = None
    image_url: str | None = None
    pdf_url: str | None = None

    # Supplier links (included in detail view)
    suppliers: list[PartSupplierLinkResponse] = Field(default_factory=list)

    created_at: datetime | None = None
    updated_at: datetime | None = None


class PartListItem(BaseModel):
    """Abbreviated part info for catalog table rows (faster than full detail)."""
    id: int

    # Hierarchy names
    category_name: str | None = None
    style_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    color_id: int | None = None
    color_hex: str | None = None

    # Identity
    part_type: str = "general"
    code: str | None = None
    name: str
    brand_id: int | None = None
    brand_name: str | None = None
    manufacturer_part_number: str | None = None
    has_pending_part_number: bool = False

    # Physical
    unit_of_measure: str = "each"

    # Pricing (None if user lacks show_dollar_values)
    company_cost_price: float | None = None
    company_markup_percent: float | None = None
    company_sell_price: float | None = None

    # Stock summary
    total_stock: int = 0

    # Forecast quick view
    forecast_adu_30: float | None = None
    forecast_days_until_low: int | None = None
    forecast_suggested_order: int | None = None

    # Status flags
    is_deprecated: bool = False
    is_qr_tagged: bool = False


class PendingPartNumberItem(BaseModel):
    """An item in the Pending Part Numbers queue — branded parts missing MPN."""
    id: int
    name: str
    category_name: str | None = None
    style_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    brand_id: int | None = None
    brand_name: str | None = None
    created_at: datetime | None = None


# =================================================================
# STOCK & MOVEMENTS
# =================================================================

class StockEntry(BaseModel):
    """A single stock row — qty of a part at a specific location."""
    id: int
    part_id: int
    part_code: str | None = None
    part_name: str | None = None
    location_type: str
    location_id: int
    qty: int
    supplier_id: int | None = None
    supplier_name: str | None = None
    last_counted: str | None = None
    updated_at: datetime | None = None


class StockSummary(BaseModel):
    """Aggregated stock for a part across all locations."""
    part_id: int
    total: int = 0
    warehouse: int = 0
    pulled: int = 0
    truck: int = 0
    job: int = 0


class MovementResponse(BaseModel):
    """A stock movement log entry."""
    id: int
    part_id: int
    part_code: str | None = None
    part_name: str | None = None
    qty: int

    from_location_type: str | None = None
    from_location_id: int | None = None
    to_location_type: str | None = None
    to_location_id: int | None = None

    supplier_id: int | None = None
    supplier_name: str | None = None

    movement_type: str
    reason: str | None = None
    job_id: int | None = None

    performed_by: int
    performer_name: str | None = None
    verified_by: int | None = None
    photo_path: str | None = None
    scan_confirmed: bool = False

    unit_cost_at_move: float | None = None
    unit_sell_at_move: float | None = None

    created_at: datetime | None = None


# =================================================================
# SEARCH & FILTER PARAMS
# =================================================================

class PartSearchParams(BaseModel):
    """Query parameters for searching/filtering the parts catalog."""
    search: str | None = None              # Text search across code, name, description
    # Hierarchy filters
    category_id: int | None = None
    style_id: int | None = None
    type_id: int | None = None
    color_id: int | None = None
    # Classification filters
    part_type: str | None = None           # general or specific
    brand_id: int | None = None
    has_pending_pn: bool | None = None     # Branded parts missing manufacturer_part_number
    # Status filters
    is_deprecated: bool | None = None
    is_qr_tagged: bool | None = None
    low_stock: bool | None = None          # Only parts below min_stock_level
    # Sorting & pagination
    sort_by: str = "name"
    sort_dir: str = "asc"
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=50, ge=1, le=200)
