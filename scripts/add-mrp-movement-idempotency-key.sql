-- Idempotent DDL for mrp.meavo.app: a database-level guarantee that a once-only stock
-- posting (packing, electric, colour catch-up, export week, electric correction) cannot be
-- written to the MrpStockMovement ledger twice, plus an index for the referenceId lookups.
-- Apply with: scripts/apply-sql.sh <staging|production> scripts/add-mrp-movement-idempotency-key.sql
-- Safe to run twice. Additive only: the column is nullable with no default, existing rows
-- stay NULL, and consumers pinned to older tags keep inserting without it (NULLs never
-- collide in a unique index).
--
-- Why not UNIQUE ("referenceId", "materialId"): electric postings list the same material
-- several times under one reference (1842 such groups on staging, 27 Nov 2026), and
-- referenceId carries unrelated meanings across movement types.
--
-- Locks: ADD COLUMN without a default only changes the catalog; the index builds hold a
-- SHARE lock that blocks ledger inserts while they run (about 11k rows in production,
-- well under a second). lock_timeout makes the script fail instead of queueing behind a
-- long transaction and stalling every reader; rerun it if that happens.

BEGIN;

SET LOCAL lock_timeout = '5s';

ALTER TABLE "MrpStockMovement"
  ADD COLUMN IF NOT EXISTS "idempotencyKey" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "MrpStockMovement_idempotencyKey_key"
  ON "MrpStockMovement"("idempotencyKey");

CREATE INDEX IF NOT EXISTS "MrpStockMovement_referenceId_idx"
  ON "MrpStockMovement"("referenceId");

COMMIT;
