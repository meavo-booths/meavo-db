-- HR documentation: optional company association and PDF brand colour.
-- Apply: scripts/apply-sql.sh staging scripts/add-document-template-settings.sql
-- Production: from the approved release tag through scripts/apply-sql.sh production.
BEGIN;
ALTER TABLE "DocumentTemplate" ADD COLUMN IF NOT EXISTS "company" "Company";
ALTER TABLE "DocumentTemplate" ADD COLUMN IF NOT EXISTS "brandColor" TEXT NOT NULL DEFAULT '';
COMMIT;
