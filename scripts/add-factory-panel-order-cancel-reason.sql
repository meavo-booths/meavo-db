-- Idempotent DDL: reason recorded when a factory RP/IP panel order is cancelled.
-- Apply with: prisma db execute --file scripts/add-factory-panel-order-cancel-reason.sql
-- Safe to run twice.

BEGIN;

ALTER TABLE "FactoryPanelOrder"
  ADD COLUMN IF NOT EXISTS "cancelReason" TEXT;

COMMIT;
