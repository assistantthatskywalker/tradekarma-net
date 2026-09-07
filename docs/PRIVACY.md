# TradeKarma waitlist privacy

Version: waitlist-2026-09-07. Operator: That Sky Walker Enterprise, Basel, Switzerland.

## What the form collects

With your consent, the waitlist stores your normalized email address, signup time, and the version of this notice in Supabase. The information is used for the merchant pilot and TradeKarma project updates. Joining does not purchase tokens, award reputation, or guarantee access.

The server derives a daily-changing pseudonymous rate-limit key from the connection IP address to limit automated submissions. The rate-limit table does not store raw IP addresses. Rate-limit records older than 24 hours are removed during subsequent signup requests. Vercel and Supabase process network requests as hosting providers and may retain their own operational logs under their policies.

## Access and retention

The public website cannot read, list, or update email records. Database access is restricted to server-side credentials and authorized project operators. Emails are not written to application logs by the signup endpoint and are not placed on a blockchain.

Waitlist records should be reviewed for deletion after 12 months without an active pilot or renewed consent. This is an operator retention obligation, not an automatic email marketing subscription. The current integration stores interest only; outbound email and address verification are not implemented. Do not use unverified addresses for a marketing campaign without the required consent and verification process.

## Requests

You may withdraw consent or request access, correction, or deletion by contacting the project owner through your established TradeKarma contact channel. Do not post your email or personal information in a public issue. A public privacy contact and unsubscribe handling must be established before outbound campaigns begin.

## Provider references

[Supabase privacy policy](https://supabase.com/privacy) and [Vercel privacy policy](https://vercel.com/legal/privacy-policy) describe the providers' own practices. No analytics cookies or advertising trackers are added by this signup integration.
