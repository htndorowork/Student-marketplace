-- ============================================================
-- NEGOTIATED OFFERS — run in MARKETPLACE Supabase SQL Editor
-- Safe to re-run.
--
-- Backs the "💰 Make an Offer" button on negotiable listings.
-- A buyer's offer lives in listing_offers (status: pending /
-- accepted / declined / used). Only the seller can accept or
-- decline, and only through respond_to_offer() below — there is
-- no client UPDATE policy on this table, so a buyer can never
-- flip their own offer to "accepted".
--
-- Once a seller accepts an offer, place_order_paid() (from
-- escrow_system_migration.sql) charges THAT buyer the agreed
-- price for THAT listing instead of the listed price — nobody
-- else's price changes. The offer is marked "used" the moment it
-- pays for an order, so it can't be reused for a second order.
-- ============================================================

CREATE TABLE IF NOT EXISTS listing_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount numeric NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined','used')),
  message_id uuid, -- the chat message this offer was sent as, for cross-reference
  created_at timestamptz DEFAULT now(),
  responded_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_listing_offers_buyer_listing ON listing_offers(buyer_id, listing_id, status);
CREATE INDEX IF NOT EXISTS idx_listing_offers_seller ON listing_offers(seller_id, status);

ALTER TABLE listing_offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "listing_offers_read" ON listing_offers;
CREATE POLICY "listing_offers_read" ON listing_offers FOR SELECT USING (
  auth.uid() = buyer_id OR auth.uid() = seller_id
);

DROP POLICY IF EXISTS "listing_offers_insert" ON listing_offers;
CREATE POLICY "listing_offers_insert" ON listing_offers FOR INSERT WITH CHECK (
  auth.uid() = buyer_id AND auth.uid() <> seller_id
);

-- Deliberately no UPDATE/DELETE policy: status changes only happen inside
-- respond_to_offer() below (SECURITY DEFINER, bypasses RLS), so neither
-- buyer nor seller can edit an offer's amount or status directly.

-- Let messages carry a reference to the offer they represent, so the
-- chat UI can render "pending / accepted / declined" on the right bubble.
ALTER TABLE messages ADD COLUMN IF NOT EXISTS offer_id uuid REFERENCES listing_offers(id) ON DELETE SET NULL;

-- ============================================================
-- respond_to_offer: the ONLY way an offer's status can change.
-- Only the seller on the offer may call it, and only while it's
-- still pending. Posts a confirmation chat message either way so
-- both sides see the outcome in the thread (and get the existing
-- new-message notification for free).
-- ============================================================
CREATE OR REPLACE FUNCTION public.respond_to_offer(p_offer_id uuid, p_accept boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer listing_offers%ROWTYPE;
  v_title text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;

  SELECT * INTO v_offer FROM listing_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Offer not found'; END IF;
  IF v_offer.seller_id <> auth.uid() THEN RAISE EXCEPTION 'Only the seller can respond to this offer'; END IF;
  IF v_offer.status <> 'pending' THEN RAISE EXCEPTION 'This offer has already been responded to'; END IF;

  SELECT title INTO v_title FROM listings WHERE id = v_offer.listing_id;

  UPDATE listing_offers
     SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
         responded_at = now()
   WHERE id = p_offer_id;

  -- Superseded: any other still-pending offers from the same buyer on the
  -- same listing no longer make sense once one has been settled.
  UPDATE listing_offers
     SET status = 'declined', responded_at = now()
   WHERE listing_id = v_offer.listing_id AND buyer_id = v_offer.buyer_id
     AND id <> p_offer_id AND status = 'pending';

  INSERT INTO messages (listing_id, buyer_id, seller_id, sender_id, content, offer_id)
  VALUES (
    v_offer.listing_id, v_offer.buyer_id, v_offer.seller_id, auth.uid(),
    CASE WHEN p_accept
      THEN '✅ Offer accepted — R' || v_offer.amount || ' for "' || COALESCE(v_title,'this item') || '". You can now order it at that price.'
      ELSE '❌ Offer declined — R' || v_offer.amount || ' for "' || COALESCE(v_title,'this item') || '".'
    END,
    p_offer_id
  );

  RETURN jsonb_build_object('status', CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END, 'amount', v_offer.amount);
END;
$$;
GRANT EXECUTE ON FUNCTION public.respond_to_offer(uuid, boolean) TO authenticated;

-- ============================================================
-- place_order_paid: same function as escrow_system_migration.sql,
-- replaced here only to add the negotiated-price check. If this
-- buyer has an accepted, not-yet-used offer on this listing, they
-- pay that price instead of the listing's price — everyone else
-- still pays the listed price. The offer is marked "used" the
-- moment it successfully pays for an order.
-- ============================================================
CREATE OR REPLACE FUNCTION public.place_order_paid(
  p_listing_id uuid,
  p_quantity integer,
  p_delivery_method text,
  p_pargo_point_id text DEFAULT NULL,
  p_pargo_point_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer uuid := auth.uid();
  v_listing listings%ROWTYPE;
  v_seller profiles%ROWTYPE;
  v_buyer_p profiles%ROWTYPE;
  v_order_id uuid;
  v_unit_price numeric;
  v_amount numeric;
  v_offer listing_offers%ROWTYPE;
BEGIN
  IF v_buyer IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF p_quantity IS NULL OR p_quantity < 1 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
  IF p_delivery_method NOT IN ('pickup','pargo') THEN RAISE EXCEPTION 'Invalid delivery method'; END IF;
  IF p_delivery_method = 'pargo' AND (p_pargo_point_id IS NULL OR btrim(p_pargo_point_id) = '') THEN
    RAISE EXCEPTION 'Select a Pargo pickup point';
  END IF;

  SELECT * INTO v_buyer_p FROM profiles WHERE id = v_buyer;
  IF v_buyer_p.full_name IS NULL OR btrim(v_buyer_p.full_name) = ''
     OR v_buyer_p.whatsapp IS NULL OR btrim(v_buyer_p.whatsapp) = '' THEN
    RAISE EXCEPTION 'Add your name and WhatsApp on your profile before ordering';
  END IF;

  SELECT * INTO v_listing FROM listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found'; END IF;
  IF COALESCE(v_listing.is_draft, false) OR NOT COALESCE(v_listing.is_available, true) THEN
    RAISE EXCEPTION 'Listing unavailable';
  END IF;
  IF COALESCE(v_listing.quantity, 0) < p_quantity THEN
    RAISE EXCEPTION 'Not enough stock';
  END IF;

  SELECT * INTO v_seller FROM profiles WHERE id = v_listing.seller_id;
  IF COALESCE(v_seller.is_blocked, false) THEN RAISE EXCEPTION 'Seller unavailable'; END IF;

  -- Negotiated price check: this buyer's most recent accepted-but-unused
  -- offer on this exact listing, if any, wins over the listed price.
  SELECT * INTO v_offer FROM listing_offers
   WHERE listing_id = p_listing_id AND buyer_id = v_buyer AND status = 'accepted'
   ORDER BY responded_at DESC LIMIT 1 FOR UPDATE;

  IF FOUND THEN
    v_unit_price := v_offer.amount;
  ELSE
    v_unit_price := CASE WHEN COALESCE(v_listing.discount_percent,0) > 0
      THEN ROUND(v_listing.price * (1 - v_listing.discount_percent / 100.0))
      ELSE v_listing.price END;
  END IF;
  v_amount := v_unit_price * p_quantity;

  -- Reserve stock immediately so two buyers can't both "win" it while one
  -- is off paying. If payment fails/expires, release-expired-escrows (or
  -- the tradesafe-webhook failure handler) puts the stock back.
  UPDATE listings SET quantity = quantity - p_quantity WHERE id = v_listing.id;

  INSERT INTO orders (
    listing_id, seller_id, buyer_id, buyer_name, buyer_whatsapp, quantity, status,
    amount, payment_status, escrow_status, delivery_method, pargo_point_id, pargo_point_name
  ) VALUES (
    v_listing.id, v_listing.seller_id, v_buyer, v_buyer_p.full_name, v_buyer_p.whatsapp, p_quantity, 'confirmed',
    v_amount, 'unpaid', 'none', p_delivery_method, p_pargo_point_id, p_pargo_point_name
  ) RETURNING id INTO v_order_id;

  IF v_offer.id IS NOT NULL THEN
    UPDATE listing_offers SET status = 'used' WHERE id = v_offer.id;
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'amount', v_amount,
    'listing_title', v_listing.title,
    'seller_id', v_seller.id,
    'seller_name', COALESCE(v_seller.full_name, 'Seller'),
    'seller_tradesafe_token', v_seller.tradesafe_token_id,
    'buyer_email', v_buyer_p.full_name -- placeholder; edge function pulls the real auth email via service role
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.place_order_paid(uuid, integer, text, text, text) TO authenticated;
