-- Quote PDF templates (owner: sales). Additive and idempotent.
-- Apply: npx prisma db execute --file scripts/add-quote-pdf-templates.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "QuotePdfBrand" AS ENUM (
    'MEAVO',
    'OFFICE_ACOUSTICS',
    'OFB'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS "QuotePdfTemplate" (
  "id" TEXT NOT NULL,
  "brand" "QuotePdfBrand" NOT NULL,
  "lang" TEXT NOT NULL,
  "termsBullets" JSONB NOT NULL,
  "footerLines" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "QuotePdfTemplate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "QuotePdfTemplate_brand_lang_key"
  ON "QuotePdfTemplate"("brand", "lang");

CREATE TABLE IF NOT EXISTS "QuotePdfMarketDefault" (
  "market" TEXT NOT NULL,
  "templateId" TEXT NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "QuotePdfMarketDefault_pkey" PRIMARY KEY ("market")
);

CREATE INDEX IF NOT EXISTS "QuotePdfMarketDefault_templateId_idx"
  ON "QuotePdfMarketDefault"("templateId");

DO $$ BEGIN
  ALTER TABLE "QuotePdfMarketDefault"
    ADD CONSTRAINT "QuotePdfMarketDefault_templateId_fkey"
    FOREIGN KEY ("templateId") REFERENCES "QuotePdfTemplate"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
