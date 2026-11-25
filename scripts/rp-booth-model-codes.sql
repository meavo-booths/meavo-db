-- RP booth model codes: SO, WS, C2, C4, H1, HF, H2, H4 (BoothFamily.code, the booth
-- models master). The spellings below are BoothFamily's names and aliases plus the
-- legacy RP codes.
--
-- Rewrites the Factory code SW, the legacy RP codes (H.O, H.F, H.2, H.4) and full
-- names saved by the admin editor ("Haven Two") in:
--   rp_requests.model, internal_production_rows.model,
--   rp_panel_options.booth_model_code, rp_spare_parts.booth (comma list),
--   automation_state 'spare_parts_kits' (kit table slots).
-- STOCK / "Other" and unknown values are left as they are.
--
-- Data only, no schema change; updated_at is left alone so lists keep their order.
-- Transactional and idempotent: a second run changes nothing.
-- Apply after Meavo-RP-App and Meavo-MRP accept the new codes (both also read the old ones).
-- Apply: scripts/apply-sql.sh <staging|production> scripts/rp-booth-model-codes.sql --env-file <file> [--tag vX.Y.Z]

BEGIN;

-- Spelling key: upper-case letters and digits only ("H.2" -> H2, "Haven Two" -> HAVENTWO).
CREATE TEMP TABLE rp_booth_code_map (spelling TEXT PRIMARY KEY, code TEXT NOT NULL) ON COMMIT DROP;
INSERT INTO rp_booth_code_map (spelling, code) VALUES
  ('SO', 'SO'), ('SOHO', 'SO'),
  ('WS', 'WS'), ('SW', 'WS'), ('WORKSTATION', 'WS'), ('WORKSTAITON', 'WS'),
  ('C2', 'C2'), ('CAMDEN2', 'C2'),
  ('C4', 'C4'), ('CAMDEN4', 'C4'), ('CAMDEN7', 'C4'),
  ('H1', 'H1'), ('HO', 'H1'), ('HAVENONE', 'H1'), ('HAVEN1', 'H1'), ('MEAVOONE', 'H1'),
  ('HF', 'HF'), ('HAVENFOCUS', 'HF'), ('MEAVOFOCUS', 'HF'),
  ('H2', 'H2'), ('HAVENTWO', 'H2'), ('HAVEN2', 'H2'), ('MEAVOTWO', 'H2'),
  ('H4', 'H4'), ('HAVENFOUR', 'H4'), ('HAVEN4', 'H4'), ('MEAVOFOUR', 'H4'), ('HAVEFOUR', 'H4');

-- 1. RP and IP header model.
UPDATE "rp_requests" r
SET "model" = m.code
FROM rp_booth_code_map m
WHERE upper(regexp_replace(r."model", '[^A-Za-z0-9]', '', 'g')) = m.spelling
  AND r."model" IS DISTINCT FROM m.code;

UPDATE "internal_production_rows" r
SET "model" = m.code
FROM rp_booth_code_map m
WHERE upper(regexp_replace(r."model", '[^A-Za-z0-9]', '', 'g')) = m.spelling
  AND r."model" IS DISTINCT FROM m.code;

-- 2. Panel options, unique on (booth_model_code, panel_code). A legacy row whose
--    new-code twin already exists (for example re-synced from the Panels sheet)
--    is removed; the twin is kept active if either row was active.
UPDATE "rp_panel_options" keep
SET "is_active" = true
FROM "rp_panel_options" legacy
JOIN rp_booth_code_map m
  ON upper(regexp_replace(legacy."booth_model_code", '[^A-Za-z0-9]', '', 'g')) = m.spelling
WHERE legacy."booth_model_code" <> m.code
  AND keep."booth_model_code" = m.code
  AND keep."panel_code" = legacy."panel_code"
  AND legacy."is_active" AND NOT keep."is_active";

DELETE FROM "rp_panel_options" legacy
USING rp_booth_code_map m, "rp_panel_options" keep
WHERE upper(regexp_replace(legacy."booth_model_code", '[^A-Za-z0-9]', '', 'g')) = m.spelling
  AND legacy."booth_model_code" <> m.code
  AND keep."booth_model_code" = m.code
  AND keep."panel_code" = legacy."panel_code";

UPDATE "rp_panel_options" o
SET "booth_model_code" = m.code
FROM rp_booth_code_map m
WHERE upper(regexp_replace(o."booth_model_code", '[^A-Za-z0-9]', '', 'g')) = m.spelling
  AND o."booth_model_code" <> m.code;

-- 3. Spare part booth lists ("SO, SW, H.O" -> "SO, WS, H1"), same separators and
--    order the RP app writes; duplicates dropped, unknown tokens kept as typed.
WITH tokens AS (
  SELECT sp."id", t.ord, btrim(t.token) AS token
  FROM "rp_spare_parts" sp,
       regexp_split_to_table(sp."booth", '[,;/|]+') WITH ORDINALITY AS t(token, ord)
  WHERE sp."booth" IS NOT NULL AND btrim(sp."booth") <> ''
),
mapped AS (
  SELECT tk."id", tk.ord,
         coalesce(m.code, upper(regexp_replace(tk.token, '\s+', '', 'g'))) AS code
  FROM tokens tk
  LEFT JOIN rp_booth_code_map m
    ON upper(regexp_replace(tk.token, '[^A-Za-z0-9]', '', 'g')) = m.spelling
  WHERE tk.token <> ''
),
firsts AS (
  SELECT "id", code, min(ord) AS ord FROM mapped GROUP BY "id", code
),
rebuilt AS (
  SELECT "id", string_agg(code, ', ' ORDER BY ord) AS booth FROM firsts GROUP BY "id"
)
UPDATE "rp_spare_parts" sp
SET "booth" = rebuilt.booth
FROM rebuilt
WHERE sp."id" = rebuilt."id"
  AND sp."booth" IS DISTINCT FROM rebuilt.booth
  -- Only lists that hold a legacy code or a name; leave ALL / * lists alone.
  AND EXISTS (
    SELECT 1
    FROM regexp_split_to_table(sp."booth", '[,;/|]+') AS t(token)
    JOIN rp_booth_code_map m
      ON upper(regexp_replace(t.token, '[^A-Za-z0-9]', '', 'g')) = m.spelling
    WHERE btrim(t.token) <> m.code
  )
  AND NOT EXISTS (
    SELECT 1
    FROM regexp_split_to_table(sp."booth", '[,;/|]+') AS t(token)
    WHERE upper(regexp_replace(t.token, '\s+', '', 'g'))
          IN ('ALL', 'ALLMODELS', 'ALLMODEL', 'EVERY', 'EVERYMODEL', 'ANY', 'ANYMODEL', 'ANYMODELS', '*')
  );

-- 4. Spare-parts kit table slots (JSON text written by JSON.stringify, no spaces).
UPDATE "automation_state"
SET "value" = replace(replace(replace("value",
      '"boothModelCode":"SW"', '"boothModelCode":"WS"'),
      '"boothModelCode":"H.O"', '"boothModelCode":"H1"'),
      '"boothModelCode":"H.F"', '"boothModelCode":"HF"')
WHERE "key" = 'spare_parts_kits'
  AND ("value" LIKE '%"boothModelCode":"SW"%'
    OR "value" LIKE '%"boothModelCode":"H.O"%'
    OR "value" LIKE '%"boothModelCode":"H.F"%');

COMMIT;
