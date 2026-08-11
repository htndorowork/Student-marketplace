# PayFast + security go-live (accurate checklist)

## 1. Run SQL on the marketplace project
In Supabase SQL Editor for **`kqsqtasykdtpdrkqyaxp`**, run in order:

1. `setup_payments.sql` (if not already)
2. **`security_hardening.sql`** (required — locks profiles, admin RPCs, place_order, storage)

Until step 2 is applied, the new frontend RPCs (`place_order`, `admin_*`, etc.) will fail.

## 2. PayFast secrets (server only — never in HTML)
```bash
supabase secrets set \
  PAYFAST_MERCHANT_ID=your_id \
  PAYFAST_MERCHANT_KEY=your_key \
  PAYFAST_PASSPHRASE=your_passphrase \
  PAYFAST_SANDBOX=true \
  --project-ref kqsqtasykdtpdrkqyaxp
```

Set `PAYFAST_SANDBOX=false` for live.

## 3. Deploy edge functions
```bash
supabase functions deploy payfast-checkout --project-ref kqsqtasykdtpdrkqyaxp
supabase functions deploy payfast-itn --no-verify-jwt --project-ref kqsqtasykdtpdrkqyaxp
```

- `payfast-checkout` — JWT required (seller must be signed in)
- `payfast-itn` — no JWT (PayFast server callback)

## 4. Admin
- Emergency paywall **OFF** for normal selling
- Sellers still need R159 / R49 paid plan
- Use **+30d / +7d** buttons (calls `admin_extend_subscription`)

## 5. Hosting
Serve the site over HTTPS. PayFast return/cancel URLs are built from the browser location.

## What the hardening actually fixed
| Issue | Fix |
|--------|-----|
| Self-grant admin / free sub | Trigger blocks privileged column changes |
| Admin mark-paid/block broken | `admin_*` SECURITY DEFINER RPCs |
| Open orders + no stock drop | `place_order` RPC; insert requires buyer = auth.uid() |
| Buyer cancel failed | `buyer_cancel_order` RPC |
| PayFast passphrase in browser | Removed; signing in `payfast-checkout` |
| Weak ITN | Require signature, fail on validate error, match amount to pending row |
| Unpaid listings visible | Browse/store require paid-until ≥ today (admins exempt) |
| WhatsApp on browse | Removed from listings select; returned only from `place_order` |
| Anyone upload images | Auth required; path must be `{userId}/...` |
