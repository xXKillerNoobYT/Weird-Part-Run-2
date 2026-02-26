/**
 * Parts API functions — hierarchy, catalog CRUD, type-color links,
 * catalog groups, brands, suppliers, brand-supplier links,
 * pending part numbers, stock, import/export.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
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
  const { data } = await apiClient.get<ApiResponse<HierarchyTree>>('/parts/hierarchy');
  return data.data!;
}

// ── Categories ──────────────────────────────────────────────────

/** List all part categories with child counts. */
export async function listCategories(params?: { search?: string; is_active?: boolean }): Promise<PartCategory[]> {
  const { data } = await apiClient.get<ApiResponse<PartCategory[]>>('/parts/categories', { params });
  return data.data ?? [];
}

/** Create a new part category. */
export async function createCategory(body: PartCategoryCreate): Promise<PartCategory> {
  const { data } = await apiClient.post<ApiResponse<PartCategory>>('/parts/categories', body);
  return data.data!;
}

/** Update a part category. */
export async function updateCategory(categoryId: number, body: PartCategoryUpdate): Promise<PartCategory> {
  const { data } = await apiClient.put<ApiResponse<PartCategory>>(`/parts/categories/${categoryId}`, body);
  return data.data!;
}

/** Delete a part category. */
export async function deleteCategory(categoryId: number): Promise<void> {
  await apiClient.delete(`/parts/categories/${categoryId}`);
}

// ── Styles ──────────────────────────────────────────────────────

/** List styles for a category. */
export async function listStylesByCategory(categoryId: number, params?: { is_active?: boolean }): Promise<PartStyle[]> {
  const { data } = await apiClient.get<ApiResponse<PartStyle[]>>(`/parts/categories/${categoryId}/styles`, { params });
  return data.data ?? [];
}

/** Create a new style. */
export async function createStyle(body: PartStyleCreate): Promise<PartStyle> {
  const { data } = await apiClient.post<ApiResponse<PartStyle>>('/parts/styles', body);
  return data.data!;
}

/** Update a style. */
export async function updateStyle(styleId: number, body: PartStyleUpdate): Promise<PartStyle> {
  const { data } = await apiClient.put<ApiResponse<PartStyle>>(`/parts/styles/${styleId}`, body);
  return data.data!;
}

/** Delete a style. */
export async function deleteStyle(styleId: number): Promise<void> {
  await apiClient.delete(`/parts/styles/${styleId}`);
}

// ── Types ───────────────────────────────────────────────────────

/** List types for a style. */
export async function listTypesByStyle(styleId: number, params?: { is_active?: boolean }): Promise<PartType[]> {
  const { data } = await apiClient.get<ApiResponse<PartType[]>>(`/parts/styles/${styleId}/types`, { params });
  return data.data ?? [];
}

/** Create a new type. */
export async function createType(body: PartTypeCreate): Promise<PartType> {
  const { data } = await apiClient.post<ApiResponse<PartType>>('/parts/types', body);
  return data.data!;
}

/** Update a type. */
export async function updateType(typeId: number, body: PartTypeUpdate): Promise<PartType> {
  const { data } = await apiClient.put<ApiResponse<PartType>>(`/parts/types/${typeId}`, body);
  return data.data!;
}

/** Delete a type. */
export async function deleteType(typeId: number): Promise<void> {
  await apiClient.delete(`/parts/types/${typeId}`);
}

// ── Type ↔ Color Links ──────────────────────────────────────────

/** Get all colors linked to a specific type. */
export async function listTypeColors(typeId: number): Promise<TypeColorLink[]> {
  const { data } = await apiClient.get<ApiResponse<TypeColorLink[]>>(`/parts/types/${typeId}/colors`);
  return data.data ?? [];
}

/** Link one or more colors to a type (bulk, idempotent). */
export async function linkColorsToType(typeId: number, colorIds: number[]): Promise<TypeColorLink[]> {
  const { data } = await apiClient.post<ApiResponse<TypeColorLink[]>>(`/parts/types/${typeId}/colors`, colorIds);
  return data.data ?? [];
}

/** Unlink a specific color from a type. */
export async function unlinkColorFromType(typeId: number, colorId: number): Promise<void> {
  await apiClient.delete(`/parts/types/${typeId}/colors/${colorId}`);
}

// ── Type ↔ Brand Links ─────────────────────────────────────────

/** Get all brand links (including General) for a type. */
export async function listTypeBrands(typeId: number): Promise<TypeBrandLink[]> {
  const { data } = await apiClient.get<ApiResponse<TypeBrandLink[]>>(`/parts/types/${typeId}/brands`);
  return data.data ?? [];
}

/** Link a brand (or General with brandId=null) to a type. */
export async function linkBrandToType(typeId: number, brandId: number | null): Promise<TypeBrandLink> {
  const { data } = await apiClient.post<ApiResponse<TypeBrandLink>>(
    `/parts/types/${typeId}/brands`,
    { type_id: typeId, brand_id: brandId },
  );
  return data.data!;
}

/** Unlink a brand (or General with brandId=0) from a type. */
export async function unlinkBrandFromType(typeId: number, brandId: number | null): Promise<void> {
  const urlBrandId = brandId === null ? 0 : brandId;
  await apiClient.delete(`/parts/types/${typeId}/brands/${urlBrandId}`);
}

/** List parts under a specific type + brand (or General) combo. */
export async function listPartsForTypeBrand(typeId: number, brandId: number | null): Promise<PartListItem[]> {
  const urlBrandId = brandId === null ? 0 : brandId;
  const { data } = await apiClient.get<ApiResponse<PartListItem[]>>(
    `/parts/types/${typeId}/brands/${urlBrandId}/parts`,
  );
  return data.data ?? [];
}

/** Quick-create a part under a type + brand combo (only needs color_id). */
export async function quickCreatePart(typeId: number, brandId: number | null, colorId: number): Promise<Part> {
  const urlBrandId = brandId === null ? 0 : brandId;
  const { data } = await apiClient.post<ApiResponse<Part>>(
    `/parts/types/${typeId}/brands/${urlBrandId}/parts`,
    { color_id: colorId } as QuickCreatePartRequest,
  );
  return data.data!;
}

// ── Colors ──────────────────────────────────────────────────────

/** List all part colors with usage counts. */
export async function listColors(params?: { search?: string; is_active?: boolean }): Promise<PartColor[]> {
  const { data } = await apiClient.get<ApiResponse<PartColor[]>>('/parts/colors', { params });
  return data.data ?? [];
}

/** Create a new color. */
export async function createColor(body: PartColorCreate): Promise<PartColor> {
  const { data } = await apiClient.post<ApiResponse<PartColor>>('/parts/colors', body);
  return data.data!;
}

/** Update a color. */
export async function updateColor(colorId: number, body: PartColorUpdate): Promise<PartColor> {
  const { data } = await apiClient.put<ApiResponse<PartColor>>(`/parts/colors/${colorId}`, body);
  return data.data!;
}

/** Delete a color. */
export async function deleteColor(colorId: number): Promise<void> {
  await apiClient.delete(`/parts/colors/${colorId}`);
}


// ═══════════════════════════════════════════════════════════════
// CATALOG
// ═══════════════════════════════════════════════════════════════

/** List parts with search, hierarchy filters, sort, and pagination. */
export async function listParts(params: PartSearchParams = {}): Promise<PaginatedData<PartListItem>> {
  const { data } = await apiClient.get<ApiResponse<PaginatedData<PartListItem>>>('/parts/catalog', {
    params,
  });
  return data.data!;
}

/** Get full detail for a single part. */
export async function getPart(partId: number): Promise<Part> {
  const { data } = await apiClient.get<ApiResponse<Part>>(`/parts/catalog/${partId}`);
  return data.data!;
}

/** Create a new part. */
export async function createPart(body: PartCreate): Promise<Part> {
  const { data } = await apiClient.post<ApiResponse<Part>>('/parts/catalog', body);
  return data.data!;
}

/** Update an existing part. */
export async function updatePart(partId: number, body: PartUpdate): Promise<Part> {
  const { data } = await apiClient.put<ApiResponse<Part>>(`/parts/catalog/${partId}`, body);
  return data.data!;
}

/** Delete a part (only works if no stock exists). */
export async function deletePart(partId: number): Promise<void> {
  await apiClient.delete(`/parts/catalog/${partId}`);
}

/** Get catalog summary stats. */
export async function getCatalogStats(): Promise<CatalogStats> {
  const { data } = await apiClient.get<ApiResponse<CatalogStats>>('/parts/catalog/stats');
  return data.data!;
}

/** Get catalog as grouped product cards (category × brand). */
export async function getCatalogGroups(params?: {
  search?: string;
  category_id?: number;
  is_deprecated?: boolean;
}): Promise<CatalogGroup[]> {
  const { data } = await apiClient.get<ApiResponse<CatalogGroup[]>>('/parts/catalog/groups', { params });
  return data.data ?? [];
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
  const { data } = await apiClient.get<ApiResponse<PaginatedData<PendingPartNumberItem>>>(
    '/parts/pending-part-numbers',
    { params },
  );
  return data.data!;
}

/** Get count of pending part numbers (for badge). */
export async function getPendingPartNumbersCount(): Promise<number> {
  const { data } = await apiClient.get<ApiResponse<{ count: number }>>('/parts/pending-part-numbers/count');
  return data.data!.count;
}


// ═══════════════════════════════════════════════════════════════
// PRICING
// ═══════════════════════════════════════════════════════════════

/** Update pricing for a part (requires edit_pricing permission). */
export async function updatePartPricing(partId: number, body: PartPricingUpdate): Promise<void> {
  await apiClient.put(`/parts/catalog/${partId}/pricing`, body);
}


// ═══════════════════════════════════════════════════════════════
// STOCK
// ═══════════════════════════════════════════════════════════════

/** Get stock levels for a part across all locations. */
export async function getPartStock(partId: number): Promise<StockEntry[]> {
  const { data } = await apiClient.get<ApiResponse<StockEntry[]>>(`/parts/catalog/${partId}/stock`);
  return data.data ?? [];
}

/** Get aggregated stock summary for a part. */
export async function getPartStockSummary(partId: number): Promise<StockSummary> {
  const { data } = await apiClient.get<ApiResponse<StockSummary>>(`/parts/catalog/${partId}/stock/summary`);
  return data.data!;
}


// ═══════════════════════════════════════════════════════════════
// PART ↔ SUPPLIER LINKS
// ═══════════════════════════════════════════════════════════════

/** Link a supplier to a part. */
export async function addPartSupplierLink(partId: number, body: PartSupplierLinkCreate): Promise<void> {
  await apiClient.post(`/parts/catalog/${partId}/suppliers`, body);
}

/** Remove a supplier link from a part. */
export async function removePartSupplierLink(partId: number, linkId: number): Promise<void> {
  await apiClient.delete(`/parts/catalog/${partId}/suppliers/${linkId}`);
}


// ═══════════════════════════════════════════════════════════════
// BRANDS
// ═══════════════════════════════════════════════════════════════

/** List all brands (with part counts and supplier counts). */
export async function listBrands(params?: { search?: string; is_active?: boolean }): Promise<Brand[]> {
  const { data } = await apiClient.get<ApiResponse<Brand[]>>('/parts/brands', { params });
  return data.data ?? [];
}

/** Get a single brand. */
export async function getBrand(brandId: number): Promise<Brand> {
  const { data } = await apiClient.get<ApiResponse<Brand>>(`/parts/brands/${brandId}`);
  return data.data!;
}

/** Create a new brand. */
export async function createBrand(body: BrandCreate): Promise<Brand> {
  const { data } = await apiClient.post<ApiResponse<Brand>>('/parts/brands', body);
  return data.data!;
}

/** Update a brand. */
export async function updateBrand(brandId: number, body: BrandUpdate): Promise<Brand> {
  const { data } = await apiClient.put<ApiResponse<Brand>>(`/parts/brands/${brandId}`, body);
  return data.data!;
}

/** Delete a brand. */
export async function deleteBrand(brandId: number): Promise<void> {
  await apiClient.delete(`/parts/brands/${brandId}`);
}


// ═══════════════════════════════════════════════════════════════
// BRAND ↔ SUPPLIER LINKS
// ═══════════════════════════════════════════════════════════════

/** Get all suppliers that carry a brand. */
export async function getBrandSuppliers(brandId: number): Promise<BrandSupplierLink[]> {
  const { data } = await apiClient.get<ApiResponse<BrandSupplierLink[]>>(`/parts/brands/${brandId}/suppliers`);
  return data.data ?? [];
}

/** Get all brands carried by a supplier. */
export async function getSupplierBrands(supplierId: number): Promise<BrandSupplierLink[]> {
  const { data } = await apiClient.get<ApiResponse<BrandSupplierLink[]>>(`/parts/suppliers/${supplierId}/brands`);
  return data.data ?? [];
}

/** Create a brand-supplier link. */
export async function createBrandSupplierLink(body: BrandSupplierLinkCreate): Promise<BrandSupplierLink> {
  const { data } = await apiClient.post<ApiResponse<BrandSupplierLink>>('/parts/brand-supplier-links', body);
  return data.data!;
}

/** Delete a brand-supplier link. */
export async function deleteBrandSupplierLink(linkId: number): Promise<void> {
  await apiClient.delete(`/parts/brand-supplier-links/${linkId}`);
}


// ═══════════════════════════════════════════════════════════════
// SUPPLIERS
// ═══════════════════════════════════════════════════════════════

/** List all suppliers (with brand counts). */
export async function listSuppliers(params?: { search?: string; is_active?: boolean }): Promise<Supplier[]> {
  const { data } = await apiClient.get<ApiResponse<Supplier[]>>('/parts/suppliers', { params });
  return data.data ?? [];
}

/** Create a new supplier. */
export async function createSupplier(body: SupplierCreate): Promise<Supplier> {
  const { data } = await apiClient.post<ApiResponse<Supplier>>('/parts/suppliers', body);
  return data.data!;
}

/** Update a supplier. */
export async function updateSupplier(supplierId: number, body: SupplierUpdate): Promise<Supplier> {
  const { data } = await apiClient.put<ApiResponse<Supplier>>(`/parts/suppliers/${supplierId}`, body);
  return data.data!;
}

/** Delete a supplier. */
export async function deleteSupplier(supplierId: number): Promise<void> {
  await apiClient.delete(`/parts/suppliers/${supplierId}`);
}


// ═══════════════════════════════════════════════════════════════
// FORECASTING
// ═══════════════════════════════════════════════════════════════

/** Get forecasting data for all parts. */
export async function getForecasting(params?: { page?: number; page_size?: number }): Promise<PaginatedData<ForecastItem>> {
  const { data } = await apiClient.get<ApiResponse<PaginatedData<ForecastItem>>>('/parts/forecasting', { params });
  return data.data!;
}


// ═══════════════════════════════════════════════════════════════
// IMPORT / EXPORT
// ═══════════════════════════════════════════════════════════════

/** Export all parts as CSV (triggers download). */
export async function exportPartsCsv(): Promise<Blob> {
  const { data } = await apiClient.get('/parts/export', {
    responseType: 'blob',
  });
  return data;
}

/** Import parts from a CSV file. */
export async function importPartsCsv(file: File): Promise<ImportResult> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<ImportResult>>('/parts/import', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
  return data.data!;
}


// ═══════════════════════════════════════════════════════════════
// COMPANION RULES
// ═══════════════════════════════════════════════════════════════

/** List all companion rules with sources and targets. */
export async function listCompanionRules(): Promise<CompanionRule[]> {
  const { data } = await apiClient.get<ApiResponse<CompanionRule[]>>('/parts/companions/rules');
  return data.data ?? [];
}

/** Create a new companion rule with sources and targets. */
export async function createCompanionRule(body: CompanionRuleCreate): Promise<CompanionRule> {
  const { data } = await apiClient.post<ApiResponse<CompanionRule>>('/parts/companions/rules', body);
  return data.data!;
}

/** Update an existing companion rule. */
export async function updateCompanionRule(ruleId: number, body: CompanionRuleUpdate): Promise<CompanionRule> {
  const { data } = await apiClient.put<ApiResponse<CompanionRule>>(`/parts/companions/rules/${ruleId}`, body);
  return data.data!;
}

/** Delete a companion rule. */
export async function deleteCompanionRule(ruleId: number): Promise<void> {
  await apiClient.delete(`/parts/companions/rules/${ruleId}`);
}


// ═══════════════════════════════════════════════════════════════
// COMPANION SUGGESTIONS
// ═══════════════════════════════════════════════════════════════

/** Manually trigger suggestion generation from input items. */
export async function generateCompanionSuggestions(body: ManualTriggerRequest): Promise<CompanionSuggestion[]> {
  const { data } = await apiClient.post<ApiResponse<CompanionSuggestion[]>>('/parts/companions/generate', body);
  return data.data ?? [];
}

/** List suggestions, optionally filtered by status. */
export async function listCompanionSuggestions(params?: {
  status?: string;
  page?: number;
  page_size?: number;
}): Promise<CompanionSuggestion[]> {
  const { data } = await apiClient.get<ApiResponse<CompanionSuggestion[]>>('/parts/companions/suggestions', { params });
  return data.data ?? [];
}

/** Approve or discard a suggestion. */
export async function decideCompanionSuggestion(
  suggestionId: number,
  body: SuggestionDecision,
): Promise<CompanionSuggestion> {
  const { data } = await apiClient.post<ApiResponse<CompanionSuggestion>>(
    `/parts/companions/suggestions/${suggestionId}/decide`,
    body,
  );
  return data.data!;
}


// ═══════════════════════════════════════════════════════════════
// COMPANION STATS & CO-OCCURRENCE
// ═══════════════════════════════════════════════════════════════

/** Get companion dashboard stats. */
export async function getCompanionStats(): Promise<CompanionStats> {
  const { data } = await apiClient.get<ApiResponse<CompanionStats>>('/parts/companions/stats');
  return data.data!;
}

/** Get top co-occurrence pairs. */
export async function getCoOccurrences(limit = 50): Promise<CoOccurrencePair[]> {
  const { data } = await apiClient.get<ApiResponse<CoOccurrencePair[]>>('/parts/companions/co-occurrence', {
    params: { limit },
  });
  return data.data ?? [];
}

/** Refresh co-occurrence pairs from stock movements. */
export async function refreshCoOccurrence(): Promise<string> {
  const { data } = await apiClient.post<ApiResponse>('/parts/companions/co-occurrence/refresh');
  return data.message ?? 'Refreshed';
}


// ═══════════════════════════════════════════════════════════════
// PART ALTERNATIVES
// ═══════════════════════════════════════════════════════════════

/** List alternatives for a part (bidirectional). */
export async function listPartAlternatives(partId: number): Promise<PartAlternative[]> {
  const { data } = await apiClient.get<ApiResponse<PartAlternative[]>>(`/parts/catalog/${partId}/alternatives`);
  return data.data ?? [];
}

/** Link an alternative part. */
export async function linkPartAlternative(partId: number, body: PartAlternativeCreate): Promise<PartAlternative> {
  const { data } = await apiClient.post<ApiResponse<PartAlternative>>(`/parts/catalog/${partId}/alternatives`, body);
  return data.data!;
}

/** Update an alternative link. */
export async function updatePartAlternative(linkId: number, body: PartAlternativeUpdate): Promise<PartAlternative> {
  const { data } = await apiClient.put<ApiResponse<PartAlternative>>(`/parts/alternatives/${linkId}`, body);
  return data.data!;
}

/** Remove an alternative link. */
export async function unlinkPartAlternative(linkId: number): Promise<void> {
  await apiClient.delete(`/parts/alternatives/${linkId}`);
}
