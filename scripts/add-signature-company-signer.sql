-- Targeted migration: company signer columns on SignatureRequest (gateway).
-- Additive and idempotent — safe to run repeatedly.
-- Apply: npx prisma db execute --file scripts/add-signature-company-signer.sql --schema prisma/schema.prisma

ALTER TABLE "SignatureRequest"
  ADD COLUMN IF NOT EXISTS "companySignerUserId" TEXT,
  ADD COLUMN IF NOT EXISTS "companySignerEmail" TEXT;

CREATE INDEX IF NOT EXISTS "SignatureRequest_companySignerUserId_idx"
  ON "SignatureRequest"("companySignerUserId");

DO $$ BEGIN
  ALTER TABLE "SignatureRequest"
    ADD CONSTRAINT "SignatureRequest_companySignerUserId_fkey"
    FOREIGN KEY ("companySignerUserId") REFERENCES "User"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
