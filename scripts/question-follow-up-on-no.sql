-- Optional follow-up text when a Yes/No fork is answered No.
-- Existing follow-ups stay "if Yes" via the default false.
-- Additive only. Idempotent.
-- Apply: npx prisma db execute --file scripts/question-follow-up-on-no.sql --schema prisma/schema.prisma

ALTER TABLE "Question"
  ADD COLUMN IF NOT EXISTS "followUpOnNo" BOOLEAN NOT NULL DEFAULT false;
