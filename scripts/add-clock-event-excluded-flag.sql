-- Soft-exclude individual clock events from stats (rows kept).
-- Apply: npx prisma db execute --file scripts/add-clock-event-excluded-flag.sql

ALTER TABLE "clock_events"
  ADD COLUMN IF NOT EXISTS "excluded_from_stats" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "clock_events_excluded_from_stats_idx"
  ON "clock_events"("excluded_from_stats");
