/**
 * Parts API functions — hierarchy, catalog CRUD, type-color links,
 * catalog groups, brands, suppliers, brand-supplier links,
 * pending part numbers, stock, import/export.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 * In Tauri mode, adaptedRequest routes to the local TS service instead.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type { ApiResponse, PaginatedData } from '../lib/types';
import type {
  // Hierarchy
  PartCategory,
  PartCategoryCreate,
  PartCategoryUpdate,
  PartStyle,
  PartStyleCreate,
  PartStyleUpdate,
  PartType,
  PartTypeCreate,
  PartTypeUpdate,
  PartColor,
  PartColorCreate,
  PartColorUpdate,
  HierarchyTree,
  // Type ↔ Color links
  TypeColorLink,
  // Type ↔ Brand links
  TypeBrandLink,
  QuickCreatePartRequest,
  // Catalog Groups
  CatalogGroup,
  // Brands & Links
  Brand,
  BrandCreate,
  BrandUpdate,
  BrandSupplierLink,
  BrandSupplierLinkCreate,
  // Suppliers
  Supplier,
  SupplierCreate,
  SupplierUpdate,
  // Parts
  Part,
  PartListItem,
  PartCreate,
  PartUpdate,
  PartPricingUpdate,
  PartSearchParams,
  PendingPartNumberItem,
  // Part-Supplier Links
  PartSupplierLinkCreate,
  // Stock & Forecast
  StockEntry,
  StockSummary,
  CatalogStats,
  ForecastItem,
  ImportResult,
  // Companions
  CompanionRule,
  CompanionRuleCreate,
  CompanionRuleUpdate,
  CompanionSuggestion,
  SuggestionDecision,
  ManualTriggerRequest,
  CoOccurrencePair,
  CompanionStats,
  // Alternatives
  PartAlternative,
  PartAlternativeCreate,
  PartAlternativeUpdate,
} from '../lib/types';


// ═══════════════════════════════════════════════════════════════
// HIERARCHY — Tree + Category / Style / Type / Color CRUD
// ═══════════════════════════════════════════════════════════════

/** Fetch the full hierarchy tree (categories → styles → types → colors). */
export async function getHierarchy(): Promise<HierarchyTree> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<HierarchyTree>>('/parts/hierarchy');
      return data.data!;
    },
    async () => {
      const { getHierarchy: local } = await import('../local/services/parts-service');
      return await local() as unknown as HierarchyTree;
    },
  );
}

// ── Categories ──────────────────────────────────────────────────

/** List all part categories with child counts. */
export async function listCategories(params?: { search?: string; is_active?: boolean }): Promise<PartCategory[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PartCategory[]>>('/parts/categories', { params });
      return data.data ?? [];
    },
    async () => {
      const { getCategories } = await import('../local/services/parts-service');
      return await getCategories(params) as unknown as PartCategory[];
    },
  );
}

/** Create a new part category. */
export async function createCategory(body: PartCategoryCreate): Promise<PartCategory> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<PartCategory>>('/parts/categories', body);
      return data.data!;
    },
    async () => {
      const { createCategory: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as PartCategory;
    },
  );
}

/** Update a part category. */
export async function updateCategory(categoryId: number, body: PartCategoryUpdate): Promise<PartCategory> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PartCategory>>(`/parts/categories/${categoryId}`, body);
      return data.data!;
    },
    async () => {
      const { updateCategory: local } = await import('../local/services/parts-service');
      return await local(categoryId, body) as unknown as PartCategory;
    },
  );
}

/** Delete a part category. */
export async function deleteCategory(categoryId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/categories/${categoryId}`); },
    async () => {
      const { deleteCategory: local } = await import('../local/services/parts-service');
      await local(categoryId);
    },
  );
}

// ── Styles ──────────────────────────────────────────────────────

/** List styles for a category. */
export async function listStylesByCategory(categoryId: number, params?: { is_active?: boolean }): Promise<PartStyle[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PartStyle[]>>(`/parts/categories/${categoryId}/styles`, { params });
      return data.data ?? [];
    },
    async () => {
      const { listStylesByCategory: local } = await import('../local/services/parts-service');
      return await local(categoryId, params) as unknown as PartStyle[];
    },
  );
}

/** Create a new style. */
export async function createStyle(body: PartStyleCreate): Promise<PartStyle> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<PartStyle>>('/parts/styles', body);
      return data.data!;
    },
    async () => {
      const { createStyle: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as PartStyle;
    },
  );
}

/** Update a style. */
export async function updateStyle(styleId: number, body: PartStyleUpdate): Promise<PartStyle> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PartStyle>>(`/parts/styles/${styleId}`, body);
      return data.data!;
    },
    async () => {
      const { updateStyle: local } = await import('../local/services/parts-service');
      return await local(styleId, body) as unknown as PartStyle;
    },
  );
}

/** Delete a style. */
export async function deleteStyle(styleId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/styles/${styleId}`); },
    async () => {
      const { deleteStyle: local } = await import('../local/services/parts-service');
      await local(styleId);
    },
  );
}

// ── Types ───────────────────────────────────────────────────────

/** List types for a style. */
export async function listTypesByStyle(styleId: number, params?: { is_active?: boolean }): Promise<PartType[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PartType[]>>(`/parts/styles/${styleId}/types`, { params });
      return data.data ?? [];
    },
    async () => {
      const { listTypesByStyle: local } = await import('../local/services/parts-service');
      return await local(styleId, params) as unknown as PartType[];
    },
  );
}

/** Get a single type by ID with enriched context. */
export async function getType(typeId: number): Promise<PartType> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PartType>>(`/parts/types/${typeId}`);
      return data.data!;
    },
    async () => {
      const { getType: local } = await import('../local/services/parts-service');
      return await local(typeId) as unknown as PartType;
    },
  );
}

/** Create a new type. */
export async function createType(body: PartTypeCreate): Promise<PartType> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<PartType>>('/parts/types', body);
      return data.data!;
    },
    async () => {
      const { createType: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as PartType;
    },
  );
}

/** Update a type. */
export async function updateType(typeId: number, body: PartTypeUpdate): Promise<PartType> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PartType>>(`/parts/types/${typeId}`, body);
      return data.data!;
    },
    async () => {
      const { updateType: local } = await import('../local/services/parts-service');
      return await local(typeId, body) as unknown as PartType;
    },
  );
}

/** Delete a type. */
export async function deleteType(typeId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/types/${typeId}`); },
    async () => {
      const { deleteType: local } = await import('../local/services/parts-service');
      await local(typeId);
    },
  );
}

// ── Type ↔ Color Links ──────────────────────────────────────────

/** Get all colors linked to a specific type. */
export async function listTypeColors(typeId: number): Promise<TypeColorLink[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TypeColorLink[]>>(`/parts/types/${typeId}/colors`);
      return data.data ?? [];
    },
    async () => {
      const { listTypeColors: local } = await import('../local/services/parts-service');
      return await local(typeId) as unknown as TypeColorLink[];
    },
  );
}

/** Link one or more colors to a type (bulk, idempotent). */
export async function linkColorsToType(typeId: number, colorIds: number[]): Promise<TypeColorLink[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TypeColorLink[]>>(`/parts/types/${typeId}/colors`, colorIds);
      return data.data ?? [];
    },
    async () => {
      const { linkColorsToType: local } = await import('../local/services/parts-service');
      return await local(typeId, colorIds) as unknown as TypeColorLink[];
    },
  );
}

/** Unlink a specific color from a type. */
export async function unlinkColorFromType(typeId: number, colorId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/types/${typeId}/colors/${colorId}`); },
    async () => {
      const { unlinkColorFromType: local } = await import('../local/services/parts-service');
      await local(typeId, colorId);
    },
  );
}

// ── Type ↔ Brand Links ─────────────────────────────────────────

/** Get all brand links (including General) for a type. */
export async function listTypeBrands(typeId: number): Promise<TypeBrandLink[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TypeBrandLink[]>>(`/parts/types/${typeId}/brands`);
      return data.data ?? [];
    },
    async () => {
      const { listTypeBrands: local } = await import('../local/services/parts-service');
      return await local(typeId) as unknown as TypeBrandLink[];
    },
  );
}

/** Link a brand (or General with brandId=null) to a type. */
export async function linkBrandToType(typeId: number, brandId: number | null): Promise<TypeBrandLink> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TypeBrandLink>>(
        `/parts/types/${typeId}/brands`,
        { type_id: typeId, brand_id: brandId },
      );
      return data.data!;
    },
    async () => {
      const { linkBrandToType: local } = await import('../local/services/parts-service');
      return await local(typeId, brandId) as unknown as TypeBrandLink;
    },
  );
}

/** Unlink a brand (or General with brandId=0) from a type. */
export async function unlinkBrandFromType(typeId: number, brandId: number | null): Promise<void> {
  return adaptedRequest(
    async () => {
      const urlBrandId = brandId === null ? 0 : brandId;
      await apiClient.delete(`/parts/types/${typeId}/brands/${urlBrandId}`);
    },
    async () => {
      const { unlinkBrandFromType: local } = await import('../local/services/parts-service');
      await local(typeId, brandId);
    },
  );
}

/** List parts under a specific type + brand (or General) combo. */
export async function listPartsForTypeBrand(typeId: number, brandId: number | null): Promise<PartListItem[]> {
  return adaptedRequest(
    async () => {
      const urlBrandId = brandId === null ? 0 : brandId;
      const { data } = await apiClient.get<ApiResponse<PartListItem[]>>(
        `/parts/types/${typeId}/brands/${urlBrandId}/parts`,
      );
      return data.data ?? [];
    },
    async () => {
      const { listPartsForTypeBrand: local } = await import('../local/services/parts-service');
      return await local(typeId, brandId) as unknown as PartListItem[];
    },
  );
}

/** Quick-create a part under a type + brand combo (only needs color_id). */
export async function quickCreatePart(typeId: number, brandId: number | null, colorId: number): Promise<Part> {
  return adaptedRequest(
    async () => {
      const urlBrandId = brandId === null ? 0 : brandId;
      const { data } = await apiClient.post<ApiResponse<Part>>(
        `/parts/types/${typeId}/brands/${urlBrandId}/parts`,
        { color_id: colorId } as QuickCreatePartRequest,
      );
      return data.data!;
    },
    async () => {
      const { quickCreatePart: local } = await import('../local/services/parts-service');
      return await local(typeId, brandId, colorId) as unknown as Part;
    },
  );
}

// ── Colors ──────────────────────────────────────────────────────

/** List all part colors with usage counts. */
export async function listColors(params?: { search?: string; is_active?: boolean }): Promise<PartColor[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PartColor[]>>('/parts/colors', { params });
      return data.data ?? [];
    },
    async () => {
      const { listColors: local } = await import('../local/services/parts-service');
      return await local(params) as unknown as PartColor[];
    },
  );
}

/** Create a new color. */
export async function createColor(body: PartColorCreate): Promise<PartColor> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<PartColor>>('/parts/colors', body);
      return data.data!;
    },
    async () => {
      const { createColor: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as PartColor;
    },
  );
}

/** Update a color. */
export async function updateColor(colorId: number, body: PartColorUpdate): Promise<PartColor> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PartColor>>(`/parts/colors/${colorId}`, body);
      return data.data!;
    },
    async () => {
      const { updateColor: local } = await import('../local/services/parts-service');
      return await local(colorId, body) as unknown as PartColor;
    },
  );
}

/** Delete a color. */
export async function deleteColor(colorId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/colors/${colorId}`); },
    async () => {
      const { deleteColor: local } = await import('../local/services/parts-service');
      await local(colorId);
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// CATALOG
// ═══════════════════════════════════════════════════════════════

/** List parts with search, hierarchy filters, sort, and pagination. */
export async function listParts(params: PartSearchParams = {}): Promise<PaginatedData<PartListItem>> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PaginatedData<PartListItem>>>('/parts/catalog', {
        params,
      });
      return data.data!;
    },
    async () => {
      const { listParts: local } = await import('../local/services/parts-service');
      const result = await local(params);
      return result as unknown as PaginatedData<PartListItem>;
    },
  );
}

/** Get full detail for a single part. */
export async function getPart(partId: number): Promise<Part> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Part>>(`/parts/catalog/${partId}`);
      return data.data!;
    },
    async () => {
      const { getPart: local } = await import('../local/services/parts-service');
      const part = await local(partId);
      if (!part) throw new Error('Part not found');
      return part as unknown as Part;
    },
  );
}

/** Create a new part. */
export async function createPart(body: PartCreate): Promise<Part> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Part>>('/parts/catalog', body);
      return data.data!;
    },
    async () => {
      const { createPart: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as Part;
    },
  );
}

/** Update an existing part. */
export async function updatePart(partId: number, body: PartUpdate): Promise<Part> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<Part>>(`/parts/catalog/${partId}`, body);
      return data.data!;
    },
    async () => {
      const { updatePart: local } = await import('../local/services/parts-service');
      return await local(partId, body) as unknown as Part;
    },
  );
}

/** Delete a part (only works if no stock exists). */
export async function deletePart(partId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/catalog/${partId}`); },
    async () => {
      const { deletePart: local } = await import('../local/services/parts-service');
      await local(partId);
    },
  );
}

/** Get catalog summary stats. */
export async function getCatalogStats(): Promise<CatalogStats> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CatalogStats>>('/parts/catalog/stats');
      return data.data!;
    },
    async () => {
      const { getCatalogStats: local } = await import('../local/services/parts-service');
      return await local() as unknown as CatalogStats;
    },
  );
}

/** Get catalog as grouped product cards (category × brand). */
export async function getCatalogGroups(params?: {
  search?: string;
  category_id?: number;
  is_deprecated?: boolean;
}): Promise<CatalogGroup[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CatalogGroup[]>>('/parts/catalog/groups', { params });
      return data.data ?? [];
    },
    async () => {
      const { getCatalogGroups: local } = await import('../local/services/parts-service');
      return await local(params) as unknown as CatalogGroup[];
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// PENDING PART NUMBERS
// ═══════════════════════════════════════════════════════════════

/** Get pending part numbers list (branded parts missing MPN). */
export async function getPendingPartNumbers(params?: {
  brand_id?: number;
  page?: number;
  page_size?: number;
}): Promise<PaginatedData<PendingPartNumberItem>> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PaginatedData<PendingPartNumberItem>>>(
        '/parts/pending-part-numbers',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getPendingPartNumbers: local } = await import('../local/services/parts-service');
      return await local(params) as unknown as PaginatedData<PendingPartNumberItem>;
    },
  );
}

/** Get count of pending part numbers (for badge). */
export async function getPendingPartNumbersCount(): Promise<number> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<{ count: number }>>('/parts/pending-part-numbers/count');
      return data.data!.count;
    },
    async () => {
      const { getPendingPartNumbersCount: local } = await import('../local/services/parts-service');
      return await local();
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// PRICING
// ═══════════════════════════════════════════════════════════════

/** Update pricing for a part (requires edit_pricing permission). */
export async function updatePartPricing(partId: number, body: PartPricingUpdate): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.put(`/parts/catalog/${partId}/pricing`, body); },
    async () => {
      const { updatePartPricing: local } = await import('../local/services/parts-service');
      await local(partId, body);
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// STOCK
// ═══════════════════════════════════════════════════════════════

/** Get stock levels for a part across all locations. */
export async function getPartStock(partId: number): Promise<StockEntry[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<StockEntry[]>>(`/parts/catalog/${partId}/stock`);
      return data.data ?? [];
    },
    async () => {
      const { getPartStock: local } = await import('../local/services/parts-service');
      return await local(partId) as unknown as StockEntry[];
    },
  );
}

/** Get aggregated stock summary for a part. */
export async function getPartStockSummary(partId: number): Promise<StockSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<StockSummary>>(`/parts/catalog/${partId}/stock/summary`);
      return data.data!;
    },
    async () => {
      const { getPartStockSummary: local } = await import('../local/services/parts-service');
      return await local(partId) as unknown as StockSummary;
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// PART ↔ SUPPLIER LINKS
// ═══════════════════════════════════════════════════════════════

/** Link a supplier to a part. */
export async function addPartSupplierLink(partId: number, body: PartSupplierLinkCreate): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.post(`/parts/catalog/${partId}/suppliers`, body); },
    async () => {
      const { addPartSupplierLink: local } = await import('../local/services/parts-service');
      await local(partId, body);
    },
  );
}

/** Remove a supplier link from a part. */
export async function removePartSupplierLink(partId: number, linkId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/catalog/${partId}/suppliers/${linkId}`); },
    async () => {
      const { removePartSupplierLink: local } = await import('../local/services/parts-service');
      await local(partId, linkId);
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// BRANDS
// ═══════════════════════════════════════════════════════════════

/** List all brands (with part counts and supplier counts). */
export async function listBrands(params?: { search?: string; is_active?: boolean }): Promise<Brand[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Brand[]>>('/parts/brands', { params });
      return data.data ?? [];
    },
    async () => {
      const { listBrands: local } = await import('../local/services/parts-service');
      return await local(params) as unknown as Brand[];
    },
  );
}

/** Get a single brand. */
export async function getBrand(brandId: number): Promise<Brand> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Brand>>(`/parts/brands/${brandId}`);
      return data.data!;
    },
    async () => {
      const { getBrand: local } = await import('../local/services/parts-service');
      return await local(brandId) as unknown as Brand;
    },
  );
}

/** Create a new brand. */
export async function createBrand(body: BrandCreate): Promise<Brand> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Brand>>('/parts/brands', body);
      return data.data!;
    },
    async () => {
      const { createBrand: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as Brand;
    },
  );
}

/** Update a brand. */
export async function updateBrand(brandId: number, body: BrandUpdate): Promise<Brand> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<Brand>>(`/parts/brands/${brandId}`, body);
      return data.data!;
    },
    async () => {
      const { updateBrand: local } = await import('../local/services/parts-service');
      return await local(brandId, body) as unknown as Brand;
    },
  );
}

/** Delete a brand. */
export async function deleteBrand(brandId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/brands/${brandId}`); },
    async () => {
      const { deleteBrand: local } = await import('../local/services/parts-service');
      await local(brandId);
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// BRAND ↔ SUPPLIER LINKS
// ═══════════════════════════════════════════════════════════════

/** Get all suppliers that carry a brand. */
export async function getBrandSuppliers(brandId: number): Promise<BrandSupplierLink[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BrandSupplierLink[]>>(`/parts/brands/${brandId}/suppliers`);
      return data.data ?? [];
    },
    async () => {
      const { getBrandSuppliers: local } = await import('../local/services/parts-service');
      return await local(brandId) as unknown as BrandSupplierLink[];
    },
  );
}

/** Get all brands carried by a supplier. */
export async function getSupplierBrands(supplierId: number): Promise<BrandSupplierLink[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BrandSupplierLink[]>>(`/parts/suppliers/${supplierId}/brands`);
      return data.data ?? [];
    },
    async () => {
      const { getSupplierBrands: local } = await import('../local/services/parts-service');
      return await local(supplierId) as unknown as BrandSupplierLink[];
    },
  );
}

/** Create a brand-supplier link. */
export async function createBrandSupplierLink(body: BrandSupplierLinkCreate): Promise<BrandSupplierLink> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BrandSupplierLink>>('/parts/brand-supplier-links', body);
      return data.data!;
    },
    async () => {
      const { createBrandSupplierLink: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as BrandSupplierLink;
    },
  );
}

/** Delete a brand-supplier link. */
export async function deleteBrandSupplierLink(linkId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/brand-supplier-links/${linkId}`); },
    async () => {
      const { deleteBrandSupplierLink: local } = await import('../local/services/parts-service');
      await local(linkId);
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// SUPPLIERS
// ═══════════════════════════════════════════════════════════════

/** List all suppliers (with brand counts). */
export async function listSuppliers(params?: { search?: string; is_active?: boolean }): Promise<Supplier[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Supplier[]>>('/parts/suppliers', { params });
      return data.data ?? [];
    },
    async () => {
      const { listSuppliers: local } = await import('../local/services/parts-service');
      return await local(params) as unknown as Supplier[];
    },
  );
}

/** Create a new supplier. */
export async function createSupplier(body: SupplierCreate): Promise<Supplier> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Supplier>>('/parts/suppliers', body);
      return data.data!;
    },
    async () => {
      const { createSupplier: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as Supplier;
    },
  );
}

/** Update a supplier. */
export async function updateSupplier(supplierId: number, body: SupplierUpdate): Promise<Supplier> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<Supplier>>(`/parts/suppliers/${supplierId}`, body);
      return data.data!;
    },
    async () => {
      const { updateSupplier: local } = await import('../local/services/parts-service');
      return await local(supplierId, body) as unknown as Supplier;
    },
  );
}

/** Delete a supplier. */
export async function deleteSupplier(supplierId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/suppliers/${supplierId}`); },
    async () => {
      const { deleteSupplier: local } = await import('../local/services/parts-service');
      await local(supplierId);
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// FORECASTING
// ═══════════════════════════════════════════════════════════════

/** Get forecasting data for all parts. */
export async function getForecasting(params?: { page?: number; page_size?: number }): Promise<PaginatedData<ForecastItem>> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PaginatedData<ForecastItem>>>('/parts/forecasting', { params });
      return data.data!;
    },
    async () => {
      const { getForecasting: local } = await import('../local/services/parts-service');
      return await local(params) as unknown as PaginatedData<ForecastItem>;
    },
  );
}

/** Recalculate forecasts for all active parts. */
export async function recalculateForecasts(): Promise<{ recalculated: number; errors: number; total_parts: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ recalculated: number; errors: number; total_parts: number }>>('/parts/forecasting/recalculate');
      return data.data!;
    },
    async () => {
      const { recalculateForecasts: local } = await import('../local/services/parts-service');
      return await local();
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// IMPORT / EXPORT
// ═══════════════════════════════════════════════════════════════

/** Export all parts as CSV (triggers download). */
export async function exportPartsCsv(): Promise<Blob> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get('/parts/export', {
        responseType: 'blob',
      });
      return data;
    },
    async () => {
      const { exportPartsCsv: local } = await import('../local/services/parts-service');
      return await local();
    },
  );
}

/** Import parts from a CSV file. */
export async function importPartsCsv(file: File): Promise<ImportResult> {
  return adaptedRequest(
    async () => {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await apiClient.post<ApiResponse<ImportResult>>('/parts/import', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      return data.data!;
    },
    async () => {
      const { importPartsCsv: local } = await import('../local/services/parts-service');
      return await local(file) as unknown as ImportResult;
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// COMPANION RULES
// ═══════════════════════════════════════════════════════════════

/** List all companion rules with sources and targets. */
export async function listCompanionRules(): Promise<CompanionRule[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CompanionRule[]>>('/parts/companions/rules');
      return data.data ?? [];
    },
    async () => {
      const { listCompanionRules: local } = await import('../local/services/parts-service');
      return await local() as unknown as CompanionRule[];
    },
  );
}

/** Create a new companion rule with sources and targets. */
export async function createCompanionRule(body: CompanionRuleCreate): Promise<CompanionRule> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<CompanionRule>>('/parts/companions/rules', body);
      return data.data!;
    },
    async () => {
      const { createCompanionRule: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as CompanionRule;
    },
  );
}

/** Update an existing companion rule. */
export async function updateCompanionRule(ruleId: number, body: CompanionRuleUpdate): Promise<CompanionRule> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<CompanionRule>>(`/parts/companions/rules/${ruleId}`, body);
      return data.data!;
    },
    async () => {
      const { updateCompanionRule: local } = await import('../local/services/parts-service');
      return await local(ruleId, body) as unknown as CompanionRule;
    },
  );
}

/** Delete a companion rule. */
export async function deleteCompanionRule(ruleId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/companions/rules/${ruleId}`); },
    async () => {
      const { deleteCompanionRule: local } = await import('../local/services/parts-service');
      await local(ruleId);
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// COMPANION SUGGESTIONS
// ═══════════════════════════════════════════════════════════════

/** Manually trigger suggestion generation from input items. */
export async function generateCompanionSuggestions(body: ManualTriggerRequest): Promise<CompanionSuggestion[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<CompanionSuggestion[]>>('/parts/companions/generate', body);
      return data.data ?? [];
    },
    async () => {
      const { generateCompanionSuggestions: local } = await import('../local/services/parts-service');
      return await local(body) as unknown as CompanionSuggestion[];
    },
  );
}

/** List suggestions, optionally filtered by status. */
export async function listCompanionSuggestions(params?: {
  status?: string;
  page?: number;
  page_size?: number;
}): Promise<CompanionSuggestion[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CompanionSuggestion[]>>('/parts/companions/suggestions', { params });
      return data.data ?? [];
    },
    async () => {
      const { listCompanionSuggestions: local } = await import('../local/services/parts-service');
      return await local(params) as unknown as CompanionSuggestion[];
    },
  );
}

/** Approve or discard a suggestion. */
export async function decideCompanionSuggestion(
  suggestionId: number,
  body: SuggestionDecision,
): Promise<CompanionSuggestion> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<CompanionSuggestion>>(
        `/parts/companions/suggestions/${suggestionId}/decide`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { decideCompanionSuggestion: local } = await import('../local/services/parts-service');
      return await local(suggestionId, body) as unknown as CompanionSuggestion;
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// COMPANION STATS & CO-OCCURRENCE
// ═══════════════════════════════════════════════════════════════

/** Get companion dashboard stats. */
export async function getCompanionStats(): Promise<CompanionStats> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CompanionStats>>('/parts/companions/stats');
      return data.data!;
    },
    async () => {
      const { getCompanionStats: local } = await import('../local/services/parts-service');
      return await local() as unknown as CompanionStats;
    },
  );
}

/** Get top co-occurrence pairs. */
export async function getCoOccurrences(limit = 50): Promise<CoOccurrencePair[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CoOccurrencePair[]>>('/parts/companions/co-occurrence', {
        params: { limit },
      });
      return data.data ?? [];
    },
    async () => {
      const { getCoOccurrences: local } = await import('../local/services/parts-service');
      return await local(limit) as unknown as CoOccurrencePair[];
    },
  );
}

/** Refresh co-occurrence pairs from stock movements. */
export async function refreshCoOccurrence(): Promise<string> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse>('/parts/companions/co-occurrence/refresh');
      return data.message ?? 'Refreshed';
    },
    async () => {
      const { refreshCoOccurrence: local } = await import('../local/services/parts-service');
      return await local();
    },
  );
}


// ═══════════════════════════════════════════════════════════════
// PART ALTERNATIVES
// ═══════════════════════════════════════════════════════════════

/** List alternatives for a part (bidirectional). */
export async function listPartAlternatives(partId: number): Promise<PartAlternative[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PartAlternative[]>>(`/parts/catalog/${partId}/alternatives`);
      return data.data ?? [];
    },
    async () => {
      const { listPartAlternatives: local } = await import('../local/services/parts-service');
      return await local(partId) as unknown as PartAlternative[];
    },
  );
}

/** Link an alternative part. */
export async function linkPartAlternative(partId: number, body: PartAlternativeCreate): Promise<PartAlternative> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<PartAlternative>>(`/parts/catalog/${partId}/alternatives`, body);
      return data.data!;
    },
    async () => {
      const { linkPartAlternative: local } = await import('../local/services/parts-service');
      return await local(partId, body) as unknown as PartAlternative;
    },
  );
}

/** Update an alternative link. */
export async function updatePartAlternative(linkId: number, body: PartAlternativeUpdate): Promise<PartAlternative> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PartAlternative>>(`/parts/alternatives/${linkId}`, body);
      return data.data!;
    },
    async () => {
      const { updatePartAlternative: local } = await import('../local/services/parts-service');
      return await local(linkId, body) as unknown as PartAlternative;
    },
  );
}

/** Remove an alternative link. */
export async function unlinkPartAlternative(linkId: number): Promise<void> {
  return adaptedRequest(
    async () => { await apiClient.delete(`/parts/alternatives/${linkId}`); },
    async () => {
      const { unlinkPartAlternative: local } = await import('../local/services/parts-service');
      await local(linkId);
    },
  );
}
