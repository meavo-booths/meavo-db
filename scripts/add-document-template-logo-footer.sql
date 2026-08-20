-- Targeted migration: DocumentTemplate logo + footer for HR PDFs (gateway).
-- Additive and idempotent — safe to run repeatedly.
-- Apply: npx prisma db execute --file scripts/add-document-template-logo-footer.sql --schema prisma/schema.prisma

ALTER TABLE "DocumentTemplate"
  ADD COLUMN IF NOT EXISTS "logoStorageKey" TEXT,
  ADD COLUMN IF NOT EXISTS "logoFileName" TEXT,
  ADD COLUMN IF NOT EXISTS "footerText" TEXT NOT NULL DEFAULT '';
