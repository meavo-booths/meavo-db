-- Add the YES_NO_INLINE question type for assembly.meavo.app: a yes/no answer
-- rendered inline in a section (tick / cross) instead of a full-screen step.
-- Additive only. Idempotent.
-- Apply: npx prisma db execute --file scripts/questionnaire-inline-yes-no.sql --schema prisma/schema.prisma

ALTER TYPE "QuestionType" ADD VALUE IF NOT EXISTS 'YES_NO_INLINE';
