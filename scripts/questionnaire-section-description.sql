-- Editable partner-facing text for questionnaire sections (image-upload steps) in assembly.meavo.app.
-- Additive only (two nullable columns, no backfill). Idempotent.
-- Apply: npx prisma db execute --file scripts/questionnaire-section-description.sql --schema prisma/schema.prisma

ALTER TABLE "QuestionnaireSection"
  ADD COLUMN IF NOT EXISTS "description" TEXT;

ALTER TABLE "QuestionnaireSectionTranslation"
  ADD COLUMN IF NOT EXISTS "description" TEXT;
