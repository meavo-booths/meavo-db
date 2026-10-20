-- Booths and site contacts for a follow-up assembly visit (repair, aftercare,
-- moving service, info). Nullable jsonb, no backfill: null keeps showing the
-- linked sales deal. Idempotent.
-- Apply: scripts/apply-sql.sh staging scripts/assembly-visit-scope.sql

ALTER TABLE "Assembly"
  ADD COLUMN IF NOT EXISTS "visitBooths" JSONB;

ALTER TABLE "Assembly"
  ADD COLUMN IF NOT EXISTS "visitContacts" JSONB;
