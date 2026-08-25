-- Section types for assembly.meavo.app: QUESTIONS, YES_NO_FORK, IMAGE_UPLOAD.
-- Migrates existing yes/no sections and photoStep into typed sections.
-- Additive only. Idempotent.
-- Apply: npx prisma db execute --file scripts/questionnaire-section-types.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "QuestionnaireSectionType" AS ENUM ('QUESTIONS', 'YES_NO_FORK', 'IMAGE_UPLOAD');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "QuestionnaireSection"
  ADD COLUMN IF NOT EXISTS "type" "QuestionnaireSectionType" NOT NULL DEFAULT 'QUESTIONS';

ALTER TABLE "QuestionnaireSection"
  ADD COLUMN IF NOT EXISTS "photosRequired" BOOLEAN NOT NULL DEFAULT true;

-- Sections whose top-level question is full-screen Yes/No become fork sections.
UPDATE "QuestionnaireSection" s
SET "type" = 'YES_NO_FORK'
WHERE s."type" = 'QUESTIONS'
  AND EXISTS (
    SELECT 1
    FROM "Question" q
    WHERE q."sectionId" = s.id
      AND q."type" = 'YES_NO'
      AND q."parentQuestionId" IS NULL
  );

-- Questionnaires with a visible photo step get a trailing image-upload section.
INSERT INTO "QuestionnaireSection" (
  "id",
  "questionnaireId",
  "title",
  "sortOrder",
  "type",
  "photosRequired",
  "createdAt",
  "updatedAt"
)
SELECT
  'cm' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 23),
  q."id",
  'Installation photos',
  COALESCE(
    (SELECT MAX(s."sortOrder") FROM "QuestionnaireSection" s WHERE s."questionnaireId" = q."id"),
    -1
  ) + 1,
  'IMAGE_UPLOAD',
  (q."photoStep" = 'REQUIRED'),
  NOW(),
  NOW()
FROM "Questionnaire" q
WHERE q."photoStep"::text != 'HIDDEN'
  AND NOT EXISTS (
    SELECT 1
    FROM "QuestionnaireSection" s
    WHERE s."questionnaireId" = q."id"
      AND s."type" = 'IMAGE_UPLOAD'
  );
