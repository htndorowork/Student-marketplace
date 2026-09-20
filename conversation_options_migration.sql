-- ============================================================
-- CHAT OPTIONS: pin / mute / archive a conversation
-- Run in the MARKETPLACE Supabase SQL Editor. Safe to re-run.
-- ============================================================

-- ---------- 1) Per-user settings for each conversation ----------
-- A "conversation" is one row in the chat list: buyer + seller + listing.
-- thread_key is  '<buyer_id>|<seller_id>|<listing_id or "none">'  (lower-case),
-- exactly how messages.html and notify_new_message() identify a conversation.
-- These settings belong to ONE user: muting or archiving a chat never affects
-- the other person.
CREATE TABLE IF NOT EXISTS conversation_settings (
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  thread_key text NOT NULL CHECK (char_length(thread_key) <= 120),
  pinned_at timestamptz,                          -- set = pinned to the top of the list
  muted_until timestamptz,                        -- "Mute for 24 hours"
  muted_always boolean NOT NULL DEFAULT false,    -- "Mute always"
  archived_at timestamptz,                        -- set = archived
  archived_incoming_count integer NOT NULL DEFAULT 0, -- how many messages THEY had sent when it was archived;
                                                  -- a newer message from them brings the chat back (unless muted)
  PRIMARY KEY (user_id, thread_key)
);

ALTER TABLE conversation_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conv_settings_own_select" ON conversation_settings;
DROP POLICY IF EXISTS "conv_settings_own_insert" ON conversation_settings;
DROP POLICY IF EXISTS "conv_settings_own_update" ON conversation_settings;
DROP POLICY IF EXISTS "conv_settings_own_delete" ON conversation_settings;

CREATE POLICY "conv_settings_own_select" ON conversation_settings FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "conv_settings_own_insert" ON conversation_settings FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "conv_settings_own_update" ON conversation_settings FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "conv_settings_own_delete" ON conversation_settings FOR DELETE USING (auth.uid() = user_id);

-- ---------- 2) Muting is enforced on the SERVER ----------
-- Every push notification and bell notification for a new message starts as a row
-- inserted here, so if the recipient has muted the conversation we simply don't
-- create one. (Just hiding it in the app would still buzz their phone.)
-- The guard on to_regclass() means this function keeps working even if it's ever
-- created before the table exists, so it can never break sending a message.
CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient uuid;
  v_sender_name text;
  v_muted boolean := false;
BEGIN
  v_recipient := CASE WHEN NEW.sender_id = NEW.buyer_id THEN NEW.seller_id ELSE NEW.buyer_id END;

  IF to_regclass('public.conversation_settings') IS NOT NULL THEN
    SELECT (cs.muted_always OR (cs.muted_until IS NOT NULL AND cs.muted_until > now()))
      INTO v_muted
      FROM conversation_settings cs
     WHERE cs.user_id = v_recipient
       AND cs.thread_key = lower(NEW.buyer_id::text || '|' || NEW.seller_id::text || '|' || COALESCE(NEW.listing_id::text, 'none'));
  END IF;

  IF COALESCE(v_muted, false) THEN
    RETURN NEW;   -- muted: the message is delivered, but no notification / push is created
  END IF;

  SELECT COALESCE(store_name, full_name, 'Someone') INTO v_sender_name FROM profiles WHERE id = NEW.sender_id;

  INSERT INTO notifications (user_id, type, message, listing_id)
  VALUES (v_recipient, 'new_message', v_sender_name || ' sent you a message 💬', NEW.listing_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_message ON messages;
CREATE TRIGGER trg_notify_new_message
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_message();
