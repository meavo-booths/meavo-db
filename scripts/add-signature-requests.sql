-- Targeted migration: SignatureRequest for HR e-signature flow (gateway).
-- Additive and idempotent — safe to run repeatedly.
-- Apply: npx prisma db execute --file scripts/add-signature-requests.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "SignatureRequestStatus" AS ENUM ('SENT', 'COMPLETED', 'DECLINED', 'CANCELED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "SignatureRequest" (
  "id" TEXT NOT NULL,
  "generatedDocumentId" TEXT NOT NULL,
  "subjectUserId" TEXT NOT NULL,
  "provider" TEXT NOT NULL DEFAULT 'signwell',
  "externalId" TEXT NOT NULL,
  "status" "SignatureRequestStatus" NOT NULL DEFAULT 'SENT',
  "signerEmail" TEXT NOT NULL,
  "sentById" TEXT NOT NULL,
  "signedDocumentKey" TEXT,
  "employeeDocumentId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SignatureRequest_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SignatureRequest_generatedDocumentId_key"
  ON "SignatureRequest"("generatedDocumentId");

CREATE UNIQUE INDEX IF NOT EXISTS "SignatureRequest_employeeDocumentId_key"
  ON "SignatureRequest"("employeeDocumentId");

CREATE INDEX IF NOT EXISTS "SignatureRequest_externalId_idx"
  ON "SignatureRequest"("externalId");

CREATE INDEX IF NOT EXISTS "SignatureRequest_subjectUserId_idx"
  ON "SignatureRequest"("subjectUserId");

CREATE INDEX IF NOT EXISTS "SignatureRequest_status_idx"
  ON "SignatureRequest"("status");

DO $$ BEGIN
  ALTER TABLE "SignatureRequest"
    ADD CONSTRAINT "SignatureRequest_generatedDocumentId_fkey"
    FOREIGN KEY ("generatedDocumentId") REFERENCES "GeneratedDocument"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SignatureRequest"
    ADD CONSTRAINT "SignatureRequest_subjectUserId_fkey"
    FOREIGN KEY ("subjectUserId") REFERENCES "User"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SignatureRequest"
    ADD CONSTRAINT "SignatureRequest_sentById_fkey"
    FOREIGN KEY ("sentById") REFERENCES "User"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SignatureRequest"
    ADD CONSTRAINT "SignatureRequest_employeeDocumentId_fkey"
    FOREIGN KEY ("employeeDocumentId") REFERENCES "EmployeeDocument"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
