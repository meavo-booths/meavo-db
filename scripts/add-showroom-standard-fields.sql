-- Showrooms (owner: showroom): fields that replace the sheet's free text with
-- standard values, as in the other apps.
--   Showroom: countryCode (ISO 3166-1 alpha-2), responsibleUserId -> User,
--     venue / street / postcode / locality (structured address), openingHoursNote,
--     generalEmail, otherContactEmails, boothConditionNote.
--   ShowroomCheck: responsibleUserId -> User, contactEmail.
--   ShowroomBooth: serialNumber, batchCode, colour.
-- The free-text columns they replace (country, responsible, address, contactPerson)
-- stay as legacy until every consumer reads the new ones.
-- Schema only and idempotent: no data is changed. The showroom app fills the new
-- fields with its own reviewed script.
-- Apply: scripts/apply-sql.sh staging scripts/add-showroom-standard-fields.sql --env-file <staging env>

BEGIN;

ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "countryCode" TEXT NOT NULL DEFAULT '';
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "responsibleUserId" TEXT;
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "boothConditionNote" TEXT NOT NULL DEFAULT '';
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "venue" TEXT NOT NULL DEFAULT '';
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "street" TEXT NOT NULL DEFAULT '';
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "postcode" TEXT NOT NULL DEFAULT '';
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "locality" TEXT NOT NULL DEFAULT '';
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "generalEmail" TEXT NOT NULL DEFAULT '';
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "otherContactEmails" TEXT[] DEFAULT ARRAY[]::TEXT[];
ALTER TABLE "Showroom" ADD COLUMN IF NOT EXISTS "openingHoursNote" TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS "Showroom_responsibleUserId_idx" ON "Showroom"("responsibleUserId");
DO $$ BEGIN
  ALTER TABLE "Showroom" ADD CONSTRAINT "Showroom_responsibleUserId_fkey"
    FOREIGN KEY ("responsibleUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "ShowroomCheck" ADD COLUMN IF NOT EXISTS "contactEmail" TEXT NOT NULL DEFAULT '';
ALTER TABLE "ShowroomCheck" ADD COLUMN IF NOT EXISTS "responsibleUserId" TEXT;
CREATE INDEX IF NOT EXISTS "ShowroomCheck_responsibleUserId_idx" ON "ShowroomCheck"("responsibleUserId");
DO $$ BEGIN
  ALTER TABLE "ShowroomCheck" ADD CONSTRAINT "ShowroomCheck_responsibleUserId_fkey"
    FOREIGN KEY ("responsibleUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "ShowroomBooth" ADD COLUMN IF NOT EXISTS "serialNumber" INTEGER;
ALTER TABLE "ShowroomBooth" ADD COLUMN IF NOT EXISTS "batchCode" TEXT NOT NULL DEFAULT '';
ALTER TABLE "ShowroomBooth" ADD COLUMN IF NOT EXISTS "colour" TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS "ShowroomBooth_batchCode_idx" ON "ShowroomBooth"("batchCode");

COMMIT;
