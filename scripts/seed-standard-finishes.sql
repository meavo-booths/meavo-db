-- Standard finishes in Inventory (0.115.0): idempotent data, Inventory tables only.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/seed-standard-finishes.sql
-- Requires scripts/add-inventory-v1.sql. Uses no new "ProductFinish" value, so it
-- is safe before the consumer apps are released.
--
-- The seven finishes normally kept in stock exist as reviewed Inventory finishes,
-- and each carries the name Sales uses for it, so a Sales line with a standard
-- finish is matched to stock without anyone mapping it by hand:
--   WHITE_STOCK -> PURE_WHITE   BLACK_STOCK -> BLACK      OAK -> OAK_VENEER
--   SAND_YELLOW, INDIGO_BLUE, ANTIQUE_ROSE, STONE_GREEN -> the finish of the same code
-- The codes are the ones production reviewed on 16-17 November 2026. A finish that
-- already exists keeps its name and state, except that "Oak Veneer" becomes "Oak"
-- (owner decision, 17 November 2026). A Sales name someone already gave to a
-- finish is left where it is.
BEGIN;

INSERT INTO "InventoryFinish" ("id", "code", "name", "active", "reviewedAt", "createdAt", "updatedAt")
SELECT 'standard-finish-' || lower(v.code), v.code, v.name, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM (VALUES
  ('PURE_WHITE', 'White'),
  ('BLACK', 'Black'),
  ('OAK_VENEER', 'Oak'),
  ('SAND_YELLOW', 'Sand Yellow'),
  ('INDIGO_BLUE', 'Indigo Blue'),
  ('ANTIQUE_ROSE', 'Antique Rose'),
  ('STONE_GREEN', 'Stone Green')
) AS v(code, name)
ON CONFLICT ("code") DO NOTHING;

UPDATE "InventoryFinish"
SET "name" = 'Oak', "updatedAt" = CURRENT_TIMESTAMP
WHERE "code" = 'OAK_VENEER' AND "name" = 'Oak Veneer';

INSERT INTO "InventoryCatalogMapping" ("id", "sourceSystem", "sourceKind", "sourceId", "finishId", "reviewedAt", "createdAt", "updatedAt")
SELECT 'standard-sales-finish-' || lower(v.sales), 'sales', 'finish', v.sales, f."id", CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM (VALUES
  ('WHITE_STOCK', 'PURE_WHITE'),
  ('BLACK_STOCK', 'BLACK'),
  ('OAK', 'OAK_VENEER'),
  ('SAND_YELLOW', 'SAND_YELLOW'),
  ('INDIGO_BLUE', 'INDIGO_BLUE'),
  ('ANTIQUE_ROSE', 'ANTIQUE_ROSE'),
  ('STONE_GREEN', 'STONE_GREEN')
) AS v(sales, code)
JOIN "InventoryFinish" f ON f."code" = v.code AND f."active" AND f."reviewedAt" IS NOT NULL
ON CONFLICT ("sourceSystem", "sourceKind", "sourceId") DO NOTHING;

COMMIT;
