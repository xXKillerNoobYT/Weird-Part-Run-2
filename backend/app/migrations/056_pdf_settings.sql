-- 056_pdf_settings.sql
-- Seed PDF template settings for customizable PO document generation.
-- Company info (name, address, phone, email, logo) stays in company_profiles.
-- These settings control PDF-specific formatting and display preferences.

INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('pdf_accent_color',      '"#3B82F6"',  'pdf'),
    ('pdf_show_unit_prices',  'true',       'pdf'),
    ('pdf_show_extended',     'true',       'pdf'),
    ('pdf_footer_text',       '""',         'pdf'),
    ('pdf_payment_terms',     '"Net 30"',   'pdf'),
    ('pdf_delivery_notes',    '""',         'pdf');
