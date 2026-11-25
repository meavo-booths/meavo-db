-- Showrooms (owner: showroom): link booth models to the shared BoothFamily catalogue,
-- as the other apps do.
--   * ShowroomBooth."familyCode" -> BoothFamily."code", backfilled from the free-text
--     "model" column (which stays, as legacy, until every consumer reads familyCode).
--   * No separate models-on-display table: the models on display are the families of
--     the showroom's booths. The free-text Showroom."modelsOnDisplay" stays, as legacy,
--     so the showroom app can show where the sheet disagrees with the booth list.
--   * BoothFamily is not changed: its codes, names and aliases are the one global set.
--     The Showroom sheet's own shorthand ("CA2", "CA4", "HO", "Camden Two") is read
--     here only to backfill, and the showroom app rewrites the legacy text to the
--     catalogue's names and codes.
-- Additive and idempotent. Backfills only fill what is empty, so a re-run never
-- overrides an edit made in the app.
-- Apply: scripts/apply-sql.sh staging scripts/add-showroom-booth-family.sql --env-file <staging env>

BEGIN;

ALTER TABLE "ShowroomBooth" ADD COLUMN IF NOT EXISTS "familyCode" TEXT;
CREATE INDEX IF NOT EXISTS "ShowroomBooth_familyCode_idx" ON "ShowroomBooth"("familyCode");
DO $$ BEGIN
  ALTER TABLE "ShowroomBooth" ADD CONSTRAINT "ShowroomBooth_familyCode_fkey"
    FOREIGN KEY ("familyCode") REFERENCES "BoothFamily"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Booth models, by the catalogue's code, name or aliases, or the sheet's shorthand.
UPDATE "ShowroomBooth" b
SET "familyCode" = f."code"
FROM "BoothFamily" f
WHERE b."familyCode" IS NULL
  AND (lower(btrim(b."model")) = lower(f."name")
    OR lower(btrim(b."model")) = lower(f."code")
    OR lower(btrim(b."model")) = ANY (f."aliases")
    OR (f."code", lower(btrim(b."model"))) IN (VALUES
      ('C2', 'ca2'), ('C2', 'camden two'),
      ('C4', 'ca4'), ('C4', 'camden four'),
      ('H1', 'ho')));

COMMIT;
