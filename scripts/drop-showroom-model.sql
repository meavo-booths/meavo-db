-- Showrooms (owner: showroom): drop ShowroomModel, the separate models-on-display list
-- that 0.122.0 added on staging. A showroom's models on display are the families of its
-- booths (ShowroomBooth.familyCode); the legacy free text Showroom."modelsOnDisplay"
-- keeps the Check-Up sheet's list so the showroom app can show where it disagrees.
-- ShowroomModel was never released to production, where this is a no-op; on staging its
-- rows are a copy of that free text, so nothing is lost.
-- Idempotent.
-- Apply: scripts/apply-sql.sh staging scripts/drop-showroom-model.sql --env-file <staging env>

BEGIN;

DROP TABLE IF EXISTS "ShowroomModel";

COMMIT;
