-- ============================================================
-- STUDENT MARKETPLACE (NWU) — FULL DATABASE SETUP
-- Run this entire file in YOUR Supabase project's SQL Editor (New Query)
-- ============================================================

-- ===================== TABLES =====================

-- Profiles (users)
CREATE TABLE IF NOT EXISTS profiles (
  id uuid REFERENCES auth.users ON DELETE CASCADE,
  full_name text,
  whatsapp text,
  residence text,
  role text DEFAULT 'buyer',
  is_admin boolean DEFAULT false,
  created_at timestamp DEFAULT now(),
  PRIMARY KEY (id)
);

-- Listings
CREATE TABLE IF NOT EXISTS listings (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  seller_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  price numeric NOT NULL,
  category text NOT NULL,
  discount_percent numeric DEFAULT 0,
  quantity integer DEFAULT 1,
  image_url text,
  image_url_2 text,
  image_url_3 text,
  is_available boolean DEFAULT true,
  textbook_year text,
  textbook_subject text,
  electronics_subcategory text,
  clothing_subcategory text,
  food_subcategory text,
  beauty_subcategory text,
  wigs_subcategory text,
  perfumes_subcategory text,
  tutoring_subcategory text,
  accommodation_subcategory text,
  transport_subcategory text,
  services_subcategory text,
  stationary_subcategory text,
  appliances_subcategory text,
  rentals_subcategory text,
  furniture_subcategory text,
  created_at timestamp DEFAULT now()
);

-- Safe to re-run: adds the columns above if this table already existed
ALTER TABLE listings ADD COLUMN IF NOT EXISTS textbook_year text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS textbook_subject text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS electronics_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS clothing_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS food_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS beauty_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS wigs_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS perfumes_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS tutoring_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS accommodation_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS transport_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS services_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS stationary_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS appliances_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS rentals_subcategory text;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS furniture_subcategory text;

-- Orders
CREATE TABLE IF NOT EXISTS orders (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  listing_id uuid,
  seller_id uuid,
  buyer_id uuid,
  buyer_name text,
  buyer_whatsapp text,
  quantity integer DEFAULT 1,
  status text DEFAULT 'confirmed',
  created_at timestamp DEFAULT now()
);

-- Cart items (optional persistence)
CREATE TABLE IF NOT EXISTS cart_items (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  buyer_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  listing_id uuid REFERENCES listings(id) ON DELETE CASCADE,
  quantity integer DEFAULT 1,
  created_at timestamp DEFAULT now()
);

-- Settings (paywall control)
CREATE TABLE IF NOT EXISTS settings (
  key text PRIMARY KEY,
  value text
);
INSERT INTO settings (key, value) VALUES ('paywall_active', 'false')
ON CONFLICT (key) DO NOTHING;

-- ===================== FOREIGN KEYS WITH SAFE DELETE =====================

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_seller_id_fkey;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_buyer_id_fkey;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_listing_id_fkey;

ALTER TABLE orders
ADD CONSTRAINT orders_seller_id_fkey
FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE orders
ADD CONSTRAINT orders_buyer_id_fkey
FOREIGN KEY (buyer_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE orders
ADD CONSTRAINT orders_listing_id_fkey
FOREIGN KEY (listing_id) REFERENCES listings(id) ON DELETE SET NULL;

ALTER TABLE listings DROP CONSTRAINT IF EXISTS listings_seller_id_fkey;
ALTER TABLE listings
ADD CONSTRAINT listings_seller_id_fkey
FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- ===================== ROW LEVEL SECURITY =====================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- Drop any old policies (safe if they don't exist)
DROP POLICY IF EXISTS "profiles_read" ON profiles;
DROP POLICY IF EXISTS "profiles_insert" ON profiles;
DROP POLICY IF EXISTS "profiles_update" ON profiles;
DROP POLICY IF EXISTS "profiles_delete_admin" ON profiles;

DROP POLICY IF EXISTS "listings_read" ON listings;
DROP POLICY IF EXISTS "listings_insert" ON listings;
DROP POLICY IF EXISTS "listings_update_seller" ON listings;
DROP POLICY IF EXISTS "listings_update_admin" ON listings;
DROP POLICY IF EXISTS "listings_delete_seller" ON listings;
DROP POLICY IF EXISTS "listings_delete_admin" ON listings;

DROP POLICY IF EXISTS "Anyone can insert orders" ON orders;
DROP POLICY IF EXISTS "Sellers can read own orders" ON orders;
DROP POLICY IF EXISTS "Buyers can read own orders" ON orders;
DROP POLICY IF EXISTS "orders_insert" ON orders;
DROP POLICY IF EXISTS "orders_read" ON orders;
DROP POLICY IF EXISTS "orders_update" ON orders;

DROP POLICY IF EXISTS "Users manage own cart" ON cart_items;
DROP POLICY IF EXISTS "cart_manage" ON cart_items;

DROP POLICY IF EXISTS "settings_read" ON settings;
DROP POLICY IF EXISTS "settings_write" ON settings;

-- PROFILES policies
CREATE POLICY "profiles_read" ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_insert" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "profiles_delete_admin" ON profiles FOR DELETE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- LISTINGS policies
CREATE POLICY "listings_read" ON listings FOR SELECT USING (true);
CREATE POLICY "listings_insert" ON listings FOR INSERT WITH CHECK (auth.uid() = seller_id);
CREATE POLICY "listings_update_seller" ON listings FOR UPDATE USING (
  auth.uid() = seller_id AND is_available = true
);
CREATE POLICY "listings_update_admin" ON listings FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);
CREATE POLICY "listings_delete_seller" ON listings FOR DELETE USING (auth.uid() = seller_id);
CREATE POLICY "listings_delete_admin" ON listings FOR DELETE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- ORDERS policies
CREATE POLICY "orders_insert" ON orders FOR INSERT WITH CHECK (true);
CREATE POLICY "orders_read" ON orders FOR SELECT USING (
  auth.uid() = buyer_id OR auth.uid() = seller_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);
CREATE POLICY "orders_update" ON orders FOR UPDATE USING (
  auth.uid() = seller_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- CART policies
CREATE POLICY "cart_manage" ON cart_items
FOR ALL USING (auth.uid() = buyer_id) WITH CHECK (auth.uid() = buyer_id);

-- SETTINGS policies
CREATE POLICY "settings_read" ON settings FOR SELECT USING (true);
CREATE POLICY "settings_write" ON settings FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- ===================== AUTO-CREATE PROFILE ON SIGNUP =====================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, whatsapp)
  VALUES (new.id, '', '')
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ===================== STORAGE BUCKET FOR IMAGES =====================
-- NOTE: Also create a bucket named "listing-images" manually:
-- Storage -> New bucket -> name: listing-images -> Public bucket: ON

DROP POLICY IF EXISTS "Anyone can upload images" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view images" ON storage.objects;

CREATE POLICY "Anyone can upload images"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'listing-images');

CREATE POLICY "Anyone can view images"
ON storage.objects FOR SELECT
USING (bucket_id = 'listing-images');

-- ===================== ADMIN SETUP =====================
-- IMPORTANT: These two people must SIGN UP on the site FIRST
-- using these exact email addresses, THEN run this section again
-- to grant them admin access.

UPDATE profiles SET is_admin = true
WHERE id = (SELECT id FROM auth.users WHERE email = 'htndorowork@gmail.com');

-- ============================================================
-- DONE! After running this:
-- 1. Create the "listing-images" storage bucket (public) if not done
-- 2. Make sure both admin emails have signed up
-- 3. Re-run the ADMIN SETUP section above to confirm admin access
-- ============================================================
