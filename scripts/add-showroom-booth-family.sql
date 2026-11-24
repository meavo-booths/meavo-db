-- Showrooms (owner: showroom): link booth models to the shared BoothFamily catalogue,
-- as the other apps do.
--   * ShowroomBooth."familyCode" -> BoothFamily."code", backfilled from the free-text
--     "model" column (which stays, as legacy, until every consumer reads familyCode).
--   * ShowroomModel: the models on display at a showroom, by family code, backfilled
--     from the free-text Showroom."modelsOnDisplay" (also kept as legacy for now).
--   * BoothFamily."aliases": drops spellings that are not used ("camden 7", "meavo one",
--     "meavo focus", "meavo two", "meavo four", "have four") and adds the Showroom
--     sheet's ("ca2", "ca4", "ho", "camden two", "camden four").
-- Additive and idempotent. Backfills only fill what is empty, so a re-run never
-- overrides an edit made in the app.
-- Apply: scripts/apply-sql.sh staging scripts/add-showroom-booth-family.sql --env-file <staging env>

BEGIN;

UPDATE "BoothFamily" SET "aliases" = ARRAY['so']::TEXT[] WHERE "code" = 'SO';
UPDATE "BoothFamily" SET "aliases" = ARRAY['ws', 'sw']::TEXT[] WHERE "code" = 'WS';
UPDATE "BoothFamily" SET "aliases" = ARRAY['c2', 'ca2', 'camden two']::TEXT[] WHERE "code" = 'C2';
UPDATE "BoothFamily" SET "aliases" = ARRAY['c4', 'ca4', 'camden four']::TEXT[] WHERE "code" = 'C4';
UPDATE "BoothFamily" SET "aliases" = ARRAY['h1', 'h.o', 'haven 1', 'ho']::TEXT[] WHERE "code" = 'H1';
UPDATE "BoothFamily" SET "aliases" = ARRAY['hf', 'h.f']::TEXT[] WHERE "code" = 'HF';
UPDATE "BoothFamily" SET "aliases" = ARRAY['h2', 'h.2', 'haven 2']::TEXT[] WHERE "code" = 'H2';
UPDATE "BoothFamily" SET "aliases" = ARRAY['h4', 'h.4', 'haven 4']::TEXT[] WHERE "code" = 'H4';

ALTER TABLE "ShowroomBooth" ADD COLUMN IF NOT EXISTS "familyCode" TEXT;
CREATE INDEX IF NOT EXISTS "ShowroomBooth_familyCode_idx" ON "ShowroomBooth"("familyCode");
DO $$ BEGIN
  ALTER TABLE "ShowroomBooth" ADD CONSTRAINT "ShowroomBooth_familyCode_fkey"
    FOREIGN KEY ("familyCode") REFERENCES "BoothFamily"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

UPDATE "ShowroomBooth" b
SET "familyCode" = f."code"
FROM "BoothFamily" f
WHERE b."familyCode" IS NULL
  AND (lower(btrim(b."model")) = lower(f."name")
    OR lower(btrim(b."model")) = lower(f."code")
    OR lower(btrim(b."model")) = ANY (f."aliases"));

CREATE TABLE IF NOT EXISTS "ShowroomModel" (
    "showroomId" TEXT NOT NULL,
    "familyCode" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ShowroomModel_pkey" PRIMARY KEY ("showroomId", "familyCode")
);
CREATE INDEX IF NOT EXISTS "ShowroomModel_familyCode_idx" ON "ShowroomModel"("familyCode");
DO $$ BEGIN
  ALTER TABLE "ShowroomModel" ADD CONSTRAINT "ShowroomModel_showroomId_fkey"
    FOREIGN KEY ("showroomId") REFERENCES "Showroom"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "ShowroomModel" ADD CONSTRAINT "ShowroomModel_familyCode_fkey"
    FOREIGN KEY ("familyCode") REFERENCES "BoothFamily"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Models on display, from the team's shorthand ("SO, WS, CA4", "6 x SO & CA4",
-- "Haven One & Haven Focus"). Only showrooms with no ShowroomModel row yet.
INSERT INTO "ShowroomModel" ("showroomId", "familyCode")
SELECT s."id", p.code
FROM "Showroom" s
JOIN (VALUES
  ('SO', '\mso\M|\msoho\M'),
  ('WS', '\mws\M|\mworkstation\M'),
  ('C2', '\mca2\M|\mc2\M|\mcamden\s*(two|2)\M'),
  ('C4', '\mca4\M|\mc4\M|\mcamden\s*(four|4)\M'),
  ('H1', '\mh1\M|\mho\M|\mhave?n?\s*one\M'),
  ('HF', '\mhf\M|\mhaven\s*focus\M'),
  ('H2', '\mh2\M|\mhaven\s*two\M'),
  ('H4', '\mh4\M|\mhaven\s*four\M')
) AS p(code, pattern) ON s."modelsOnDisplay" ~* p.pattern
JOIN "BoothFamily" f ON f."code" = p.code
WHERE NOT EXISTS (SELECT 1 FROM "ShowroomModel" m WHERE m."showroomId" = s."id")
ON CONFLICT DO NOTHING;

COMMIT;
