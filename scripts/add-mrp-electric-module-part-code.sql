-- Add required unique partCode on electric modules.
-- Apply: npx prisma db execute --file scripts/add-mrp-electric-module-part-code.sql --schema prisma/schema.prisma

ALTER TABLE "MrpElectricModule" ADD COLUMN IF NOT EXISTS "partCode" TEXT;

UPDATE "MrpElectricModule"
SET "partCode" = "code"
WHERE "partCode" IS NULL OR btrim("partCode") = '';

CREATE UNIQUE INDEX IF NOT EXISTS "MrpElectricModule_partCode_key"
  ON "MrpElectricModule"("partCode");

ALTER TABLE "MrpElectricModule" ALTER COLUMN "partCode" SET NOT NULL;
