-- Old "Laminated Colour" rows that name a standard finish (0.115.0): idempotent data.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/convert-laminated-colour-finishes.sql
-- Requires scripts/add-standard-finishes.sql, committed.
-- RUN LAST: only after Sales, Inventory and Assembly run a Prisma client generated
-- from 0.115.0 or later. An older client fails when it reads a converted row.
--
-- Sales filed the standard colours under LDF_COLOUR with the colour typed into
-- finishDetails. Rows whose detail is exactly one of the three texts found in
-- production on 17 November 2026 (10 rows: natural oak, sand yellow, indigo blue)
-- move to the finish they name; the detail text stays as written. Every other
-- LDF_COLOUR row (no detail, or "dark oak", a colour no longer made) is left
-- alone and shows as "Laminated Colour (old)". updatedAt is not touched, so no
-- app treats the rows as edited.
BEGIN;

UPDATE "QuoteLineItem" SET "finish" = 'OAK'
WHERE "finish" = 'LDF_COLOUR' AND lower(btrim("finishDetails")) = 'natural oak';
UPDATE "QuoteLineItem" SET "finish" = 'SAND_YELLOW'
WHERE "finish" = 'LDF_COLOUR' AND lower(btrim("finishDetails")) = 'sand yellow';
UPDATE "QuoteLineItem" SET "finish" = 'INDIGO_BLUE'
WHERE "finish" = 'LDF_COLOUR' AND lower(btrim("finishDetails")) = 'indigo blue';

UPDATE "BoothUnit" SET "finish" = 'OAK'
WHERE "finish" = 'LDF_COLOUR' AND lower(btrim("finishDetails")) = 'natural oak';
UPDATE "BoothUnit" SET "finish" = 'SAND_YELLOW'
WHERE "finish" = 'LDF_COLOUR' AND lower(btrim("finishDetails")) = 'sand yellow';
UPDATE "BoothUnit" SET "finish" = 'INDIGO_BLUE'
WHERE "finish" = 'LDF_COLOUR' AND lower(btrim("finishDetails")) = 'indigo blue';

COMMIT;
