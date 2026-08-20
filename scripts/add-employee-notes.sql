-- Add free-text notes on Employee for gateway HR profiles.
-- Apply: npx prisma db execute --file scripts/add-employee-notes.sql --schema prisma/schema.prisma

ALTER TABLE "Employee"
  ADD COLUMN IF NOT EXISTS "notes" TEXT NOT NULL DEFAULT '';
