-- RP lifecycle event history for detail popups / timelines (owner: rp).
-- Additive only — safe to re-run.
-- Apply: npx prisma db execute --file scripts/add-rp-lifecycle-events.sql --schema prisma/schema.prisma
-- Or: npm run db:push (after reviewing npm run diff)

CREATE TABLE IF NOT EXISTS "rp_lifecycle_events" (
  "id"           TEXT NOT NULL,
  "entity_type"  TEXT NOT NULL,
  "entity_id"    TEXT NOT NULL,
  "event_type"   TEXT NOT NULL,
  "from_status"  TEXT,
  "to_status"    TEXT,
  "actor_email"  TEXT,
  "payload"      JSONB,
  "created_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "rp_lifecycle_events_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "rp_lifecycle_events_entity_type_entity_id_created_at_idx"
  ON "rp_lifecycle_events" ("entity_type", "entity_id", "created_at");

CREATE INDEX IF NOT EXISTS "rp_lifecycle_events_event_type_idx"
  ON "rp_lifecycle_events" ("event_type");
