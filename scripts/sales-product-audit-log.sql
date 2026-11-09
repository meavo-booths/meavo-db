-- ProductAuditLog: field-level change history for products in the sales app
-- (who changed what, when), including markets and add-on booth restrictions.
-- Rows are deleted with their product. Additive and idempotent.
-- Apply: scripts/apply-sql.sh staging scripts/sales-product-audit-log.sql --env-file <staging env>

BEGIN;

CREATE TABLE IF NOT EXISTS "ProductAuditLog" (
  "id"          TEXT NOT NULL,
  "productId"   TEXT NOT NULL,
  "actorUserId" TEXT,
  "action"      TEXT NOT NULL,
  "source"      TEXT NOT NULL DEFAULT 'FORM',
  "changes"     JSONB NOT NULL,
  "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ProductAuditLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "ProductAuditLog_productId_createdAt_idx"
  ON "ProductAuditLog"("productId", "createdAt");

CREATE INDEX IF NOT EXISTS "ProductAuditLog_actorUserId_idx"
  ON "ProductAuditLog"("actorUserId");

DO $$ BEGIN
  ALTER TABLE "ProductAuditLog"
    ADD CONSTRAINT "ProductAuditLog_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
