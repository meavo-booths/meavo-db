-- MRP performance indexes — safe to run on production without touching other schemas.
-- Apply: npx prisma db execute --file scripts/add-mrp-perf-indexes.sql --schema prisma/schema.prisma

-- Documents list: WHERE createdById = ? ORDER BY createdAt DESC
CREATE INDEX IF NOT EXISTS "MrpDocument_createdById_createdAt_idx"
  ON "MrpDocument"("createdById", "createdAt" DESC);

-- Upload dedupe: WHERE contentHash = ? AND createdById = ?
CREATE INDEX IF NOT EXISTS "MrpDocument_createdById_contentHash_idx"
  ON "MrpDocument"("createdById", "contentHash");

-- Zeron sync demote-current: WHERE documentId = ? AND isCurrent = true
CREATE INDEX IF NOT EXISTS "MrpSyncAttempt_documentId_isCurrent_idx"
  ON "MrpSyncAttempt"("documentId", "isCurrent");

-- Admin sync audit: ORDER BY attemptedAt DESC LIMIT 100
CREATE INDEX IF NOT EXISTS "MrpSyncAttempt_attemptedAt_idx"
  ON "MrpSyncAttempt"("attemptedAt" DESC);

-- Batch lookup by name (inventory checkpoints, recipe exception links) + name sort
CREATE INDEX IF NOT EXISTS "MrpManufacturingBatch_name_idx"
  ON "MrpManufacturingBatch"("name");

-- Active material lists sorted by name (materials/inventory/receipt pages)
CREATE INDEX IF NOT EXISTS "MrpMaterial_isActive_name_idx"
  ON "MrpMaterial"("isActive", "name");

-- Recipe exception list: WHERE status = ? ORDER BY createdAt DESC
CREATE INDEX IF NOT EXISTS "MrpRecipeException_status_createdAt_idx"
  ON "MrpRecipeException"("status", "createdAt" DESC);

-- MrpStockMovement is insert-only today; movementType is never queried —
-- drop the index to cut write overhead on the fastest-growing table.
DROP INDEX IF EXISTS "MrpStockMovement_movementType_idx";
