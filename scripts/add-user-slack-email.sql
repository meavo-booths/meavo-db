-- Optional Slack lookup email override on User (gateway profile).
-- Additive only. Idempotent.
-- Apply: npx prisma db execute --file scripts/add-user-slack-email.sql --schema prisma/schema.prisma

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "slackEmail" TEXT;
