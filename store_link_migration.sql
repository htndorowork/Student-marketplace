-- ============================================================
-- SELLER STOREFRONT LINK — run in MARKETPLACE Supabase SQL Editor
-- Safe to re-run.
-- ============================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS store_link text;
