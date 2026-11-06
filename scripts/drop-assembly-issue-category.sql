-- Drop the legacy Assembly.issueCategory column (0.104.0).
--
-- In July 2026 the Assembly app moved from one issue category per assembly to the
-- issueCategories list (assembly prisma/sql/issue_categories.sql copied every value
-- across). The app has not read or written issueCategory since, and no other app
-- uses it. Only meavo-db 0.103.0 declared it, and no app pins that version.
-- On 6 November 2026 production held 483 values; 477 also appear in
-- issueCategories, five more are "Light", which the list now calls "Electrics
-- problems", and one assembly's "Item missing" is the only value not kept
-- elsewhere. All 483 were exported before this drop, on the owner's decision.
--
-- Safe to run repeatedly.

BEGIN;

ALTER TABLE "Assembly" DROP COLUMN IF EXISTS "issueCategory";

COMMIT;
