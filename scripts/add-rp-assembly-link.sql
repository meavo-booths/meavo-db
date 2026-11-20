-- RP: link a replacement-part request to the assembly job it was ordered from
-- ("Order RP" on the assembly job page) and to the sale's DealID.
-- Both columns are optional and empty for every existing RP. Additive, transactional
-- and idempotent; touches no existing data.
-- Apply: scripts/apply-sql.sh staging scripts/add-rp-assembly-link.sql --env-file <staging env>
-- Production: from the approved release tag through scripts/apply-sql.sh production.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE "rp_requests" ADD COLUMN IF NOT EXISTS "assembly_id" TEXT;
ALTER TABLE "rp_requests" ADD COLUMN IF NOT EXISTS "deal_id" TEXT;

CREATE INDEX IF NOT EXISTS "rp_requests_assembly_id_idx" ON "rp_requests"("assembly_id");
CREATE INDEX IF NOT EXISTS "rp_requests_deal_id_idx" ON "rp_requests"("deal_id");

DO $$ BEGIN
  ALTER TABLE "rp_requests"
    ADD CONSTRAINT "rp_requests_assembly_id_fkey"
    FOREIGN KEY ("assembly_id") REFERENCES "Assembly"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
