/**
 * Parts API functions — catalog CRUD, brands, suppliers, stock, import/export.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import type { ApiResponse, PaginatedData } from '../lib/types';
import type {
  Part,
  PartListItem,
  PartCreate,
  PartUpdate,
  PartPricingUpdate,
  Brand,
  BrandCreate,
  BrandUpdate,
  Supplier,
  SupplierCreate,
  SupplierUpdate,
  PartSearchParams,
  StockEntry,
  StockSummary,
  PartSupplierLinkCreate,
  CatalogStats,
  ForecastItem,
  ImportResult,
} from '../lib/types';


// ═══════════════════════════════════════════════════════════════
// CATALOG
// ═══════════════════════════════════════════════════════════════

/** List parts with search, filter, sort, and pagination. */
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
// SUPPLIER LINKS
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

/** List all brands. */
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
// SUPPLIERS
// ═══════════════════════════════════════════════════════════════

/** List all suppliers. */
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
