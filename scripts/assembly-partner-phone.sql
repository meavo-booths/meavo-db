-- Optional contact phone for assembly.meavo.app partner profiles.
-- Additive only. Idempotent.
-- Apply: scripts/apply-sql.sh staging scripts/assembly-partner-phone.sql --env-file .env.staging

ALTER TABLE "AssemblyPartner"
  ADD COLUMN IF NOT EXISTS "phone" TEXT;
