-- RP partner vs end-client split (meavo-rp).
-- Renames address_book_entries.client → partner; adds rp_requests.partner.
-- Idempotent where possible.

ALTER TABLE "address_book_entries" RENAME COLUMN "client" TO "partner";

DROP INDEX IF EXISTS "address_book_entries_client_idx";
CREATE INDEX IF NOT EXISTS "address_book_entries_partner_idx" ON "address_book_entries"("partner");

ALTER TABLE "rp_requests" ADD COLUMN IF NOT EXISTS "partner" TEXT;
