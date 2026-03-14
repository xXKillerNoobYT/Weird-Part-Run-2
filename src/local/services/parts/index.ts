/**
 * Parts Service — barrel re-export.
 *
 * All domain sub-services are re-exported here so that existing
 * imports from 'parts-service' continue to work unchanged.
 */

export * from './hierarchy-service';
export * from './catalog-service';
export * from './pricing-service';
export * from './stock-service';
export * from './suppliers-service';
export * from './forecasting-service';
export * from './import-export-service';
export * from './companions-service';
export * from './alternatives-service';
