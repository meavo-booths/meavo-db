-- Optional rep comment on Sales daily-priority feedback (Helpful / Dismissed / Action taken).
-- Apply: npx prisma db execute --file scripts/sales-priority-feedback-comment.sql --schema prisma/schema.prisma
-- Prerequisite: scripts/sales-daily-priorities.sql has been applied.
-- Additive, transactional and idempotent: one nullable column, no data changes.
-- Older Sales releases name their insert columns, so they keep working unchanged.
-- Verify the actual isolated non-production target before testing. Production
-- application requires exact SQL/revision approval under RELEASE_POLICY.md.
-- Application rollback must retain this column and any saved comments.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE "SalesPriorityFeedback"
  ADD COLUMN IF NOT EXISTS "comment" TEXT;

COMMIT;
