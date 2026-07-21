-- Link ClockWorker → User and add CANCELLED pending status.
-- Apply: npx prisma db execute --file scripts/clock-workers-user-link.sql --schema prisma/schema.prisma

ALTER TYPE "ClockPendingStatus" ADD VALUE IF NOT EXISTS 'CANCELLED';

ALTER TABLE "clock_workers"
  ADD COLUMN IF NOT EXISTS "user_id" TEXT;

DO $$ BEGIN
  ALTER TABLE "clock_workers"
    ADD CONSTRAINT "clock_workers_user_id_key" UNIQUE ("user_id");
EXCEPTION
  WHEN duplicate_table THEN NULL;
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "clock_workers"
    ADD CONSTRAINT "clock_workers_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "User"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
