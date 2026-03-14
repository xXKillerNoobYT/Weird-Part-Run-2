/**
 * Shared utilities for orders API modules.
 */

/** Helper: unwrap paginated backend response -> flat items array */
export function unwrapPaginated<T>(responseData: unknown): T[] {
  if (!responseData) return [];
  if (Array.isArray(responseData)) return responseData as T[];
  // PaginatedData shape: { items: T[], total: number, ... }
  const paginated = responseData as { items?: T[] };
  return paginated.items ?? [];
}
