-- Add Portuguese as a questionnaire translation language.
-- Additive only. Idempotent.
ALTER TYPE "QuestionnaireLocale" ADD VALUE IF NOT EXISTS 'PT';
