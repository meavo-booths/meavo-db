-- Per-event-type questionnaires for assembly.meavo.app: name, served event types,
-- and whether the wizard ends with a photo step.
-- Apply: npx prisma db execute --file scripts/add-questionnaire-event-types.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "QuestionnairePhotoStep" AS ENUM ('REQUIRED', 'OPTIONAL', 'HIDDEN');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Questionnaire"
  ADD COLUMN IF NOT EXISTS "name" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "eventTypes" "AssemblyEventType"[] NOT NULL DEFAULT ARRAY[]::"AssemblyEventType"[],
  ADD COLUMN IF NOT EXISTS "photoStep" "QuestionnairePhotoStep" NOT NULL DEFAULT 'REQUIRED';

-- The pre-existing checklist is the Assembly one.
UPDATE "Questionnaire"
  SET "name" = 'Assembly',
      "eventTypes" = ARRAY['ASSEMBLY']::"AssemblyEventType"[]
  WHERE cardinality("eventTypes") = 0;
