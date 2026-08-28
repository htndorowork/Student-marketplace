# PayFast reapplication checklist

Full manual read-through of every page's copy (not just a keyword search)
is complete. Here's everything found and what was done about each.

## ✅ Fixed in the code — no action needed from you

- **No facilitator/aggregator language anywhere.** Checked every page —
  `terms.html`, `privacy.html`, `faq.html`, `index.html`, `seller.html`,
  `receipt.html`, `payment-return.html`, `payment-cancel.html`,
  `admin.html`, `guidelines.html`, `store.html`, `categories.html`,
  `favorites.html`, `login.html`, `listing-reviews.html`, `404.html`.
  Nothing describes Student Marketplace as processing, splitting, or
  holding buyer-seller money. `receipt.html` and `faq.html` already
  explicitly said payment is arranged directly between buyer and seller —
  that was good and is unchanged.
- **`terms.html`** now has an explicit section (5a) stating Student
  Marketplace never processes, holds, or facilitates buyer-seller payment.
- **`privacy.html`** now discloses PayFast by name as the processor for
  seller subscription payments specifically (payment gateways' compliance
  teams check for this), and links their privacy policy.
- **Refund/cancellation policy** for subscription payments (section 5b of
  Terms) — was already added previously.

## ⚠️ Needs YOUR real information before resubmitting — I can't fill this in

This was the other likely factor, separate from wording: **the site had no
business registration number, legal entity name, or physical address
anywhere.** Payment gateways' KYC review checks for this. I've added a
placeholder block at the top of `terms.html` — you need to replace the
bracketed placeholders with your real details:

```
[LEGAL/TRADING NAME — e.g. "Student Marketplace (Pty) Ltd" or your name if a sole proprietor]
[YOUR CIPC/COMPANY REGISTRATION NUMBER]
[YOUR PHYSICAL ADDRESS]
```

I generated none of this myself — a fabricated registration number or
address would be worse than an empty one on a payment gateway application.
If you haven't registered a business entity yet (CIPC), you may be able to
apply as a sole proprietor using your own ID/address instead — check
PayFast's specific requirements for individual/sole-proprietor merchants
when you re-apply.

## What to tell PayFast on reapplication

> Student Marketplace is a subscription-based classifieds/listing service
> for students. Sellers pay Student Marketplace directly, via PayFast, for
> access to post listings — plans range from R19 (48-hour) to R699
> (6-month). This is the ONLY payment that flows through PayFast.
>
> Student Marketplace does not process, hold, split, or facilitate any
> payment between a buyer and a seller. When a buyer wants to purchase an
> item, the platform simply shares the seller's contact details — the
> buyer and seller arrange and complete that transaction entirely outside
> the platform and outside PayFast (cash, EFT, in person, etc.).
> Student Marketplace never sees, touches, or takes a cut of that money.

## If reapplication still doesn't work

The original email said "this decision is final and cannot be appealed."
That may apply only to that specific application/reference number
(36788667) — a new application with corrected business details and
description may be reviewed fresh. If PayFast still won't approve it:

1. Contact PayFast support directly and ask whether a new application,
   correctly described as direct subscription billing (not aggregation),
   would go through standard merchant review.
2. If they decline under any framing, consider an alternative SA gateway —
   Yoco, Paystack, Ozow, or Peach Payments. The `MSpayfast` Edge Functions
   would need to be swapped for that provider's equivalent, but the rest
   of the app (`subscription_payments` table, plan activation logic) stays
   the same.
