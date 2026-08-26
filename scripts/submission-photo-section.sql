-- Link submission photos to questionnaire image-upload sections for assembly.meavo.app.
-- Additive only. Idempotent.
-- Apply: npx prisma db execute --file scripts/submission-photo-section.sql --schema prisma/schema.prisma

ALTER TABLE "SubmissionPhoto"
  ADD COLUMN IF NOT EXISTS "sectionId" TEXT;

DO $$ BEGIN
  ALTER TABLE "SubmissionPhoto" ADD CONSTRAINT "SubmissionPhoto_sectionId_fkey"
    FOREIGN KEY ("sectionId") REFERENCES "QuestionnaireSection"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "SubmissionPhoto_submissionId_sectionId_idx"
  ON "SubmissionPhoto"("submissionId", "sectionId");

-- Best-effort backfill: attach legacy photos to the first image-upload section on the
-- published questionnaire serving that assembly's event type.
UPDATE "SubmissionPhoto" sp
SET "sectionId" = matched.section_id
FROM (
  SELECT
    sp2.id AS photo_id,
    (
      SELECT s.id
      FROM "QuestionnaireSubmission" sub
      JOIN "Assembly" a ON a.id = sub."assemblyId"
      JOIN "Questionnaire" q ON q."isPublished" = true AND a."eventType" = ANY(q."eventTypes")
      JOIN "QuestionnaireSection" s ON s."questionnaireId" = q.id AND s."type" = 'IMAGE_UPLOAD'
      WHERE sub.id = sp2."submissionId"
      ORDER BY s."sortOrder" ASC
      LIMIT 1
    ) AS section_id
  FROM "SubmissionPhoto" sp2
  WHERE sp2."sectionId" IS NULL
) matched
WHERE sp.id = matched.photo_id
  AND matched.section_id IS NOT NULL;
