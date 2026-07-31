-- Apply: additive column for RP logger sibling groups (meavo-rp).
-- Idempotent.

ALTER TABLE "rp_requests" ADD COLUMN IF NOT EXISTS "linked_group_id" TEXT;

CREATE INDEX IF NOT EXISTS "rp_requests_linked_group_id_idx" ON "rp_requests"("linked_group_id");
