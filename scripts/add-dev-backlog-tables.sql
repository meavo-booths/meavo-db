-- Dev backlog for dev.meavo.app (owner: dev): families, apps, items, relations,
-- links, comments, attachments, subscribers and activity. Additive and idempotent:
-- new enums and tables only, plus foreign keys to "User".
-- Apply: scripts/apply-sql.sh staging scripts/add-dev-backlog-tables.sql --env-file <staging env>

BEGIN;

DO $$ BEGIN
  CREATE TYPE "BacklogItemType" AS ENUM ('BUG', 'FEATURE', 'IMPROVEMENT', 'CHORE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "BacklogItemStatus" AS ENUM ('TRIAGE', 'BACKLOG', 'NEXT', 'IN_PROGRESS', 'IN_REVIEW', 'ON_STAGING', 'RELEASED', 'WONT_DO');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "BacklogSeverity" AS ENUM ('URGENT', 'HIGH', 'MEDIUM', 'LOW');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "BacklogImpact" AS ENUM ('HIGH', 'MEDIUM', 'LOW');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "BacklogEffort" AS ENUM ('S', 'M', 'L');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "BacklogRelationKind" AS ENUM ('BLOCKS', 'RELATES', 'DUPLICATE_OF');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "BacklogLinkKind" AS ENUM ('PULL_REQUEST', 'COMMIT', 'REQUEST', 'TASK', 'DOC', 'OTHER');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "BacklogLinkState" AS ENUM ('OPEN', 'MERGED', 'CLOSED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "BacklogFamily" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BacklogFamily_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogApp" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "familyId" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "repoFullName" TEXT,
    "url" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "archivedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BacklogApp_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogItem" (
    "id" TEXT NOT NULL,
    "number" SERIAL NOT NULL,
    "appId" TEXT NOT NULL,
    "parentId" TEXT,
    "type" "BacklogItemType" NOT NULL,
    "status" "BacklogItemStatus" NOT NULL DEFAULT 'TRIAGE',
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "acceptanceCriteria" TEXT NOT NULL DEFAULT '',
    "needsDbChange" BOOLEAN NOT NULL DEFAULT false,
    "severity" "BacklogSeverity",
    "impact" "BacklogImpact",
    "effort" "BacklogEffort",
    "rank" TEXT NOT NULL,
    "focusRank" TEXT,
    "alsoAffects" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "ownerId" TEXT,
    "createdById" TEXT NOT NULL,
    "sourceRequestId" TEXT,
    "targetDate" DATE,
    "wontDoReason" TEXT,
    "startedAt" TIMESTAMP(3),
    "releasedAt" TIMESTAMP(3),
    "closedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BacklogItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogItemRelation" (
    "id" TEXT NOT NULL,
    "fromId" TEXT NOT NULL,
    "toId" TEXT NOT NULL,
    "kind" "BacklogRelationKind" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BacklogItemRelation_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogLink" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "kind" "BacklogLinkKind" NOT NULL,
    "url" TEXT NOT NULL,
    "title" TEXT NOT NULL DEFAULT '',
    "repoFullName" TEXT,
    "number" INTEGER,
    "state" "BacklogLinkState",
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BacklogLink_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogComment" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "authorId" TEXT NOT NULL,
    "parentId" TEXT,
    "body" TEXT NOT NULL,
    "isDecision" BOOLEAN NOT NULL DEFAULT false,
    "mentionedUserIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "resolvedAt" TIMESTAMP(3),
    "resolvedById" TEXT,
    "editedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BacklogComment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogAttachment" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "commentId" TEXT,
    "uploadedById" TEXT NOT NULL,
    "storageKey" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BacklogAttachment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogSubscriber" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BacklogSubscriber_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BacklogActivity" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "actorId" TEXT,
    "action" TEXT NOT NULL,
    "fromValue" TEXT,
    "toValue" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BacklogActivity_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "BacklogFamily_key_key" ON "BacklogFamily"("key");

CREATE UNIQUE INDEX IF NOT EXISTS "BacklogApp_key_key" ON "BacklogApp"("key");

CREATE INDEX IF NOT EXISTS "BacklogApp_familyId_sortOrder_idx" ON "BacklogApp"("familyId", "sortOrder");

CREATE UNIQUE INDEX IF NOT EXISTS "BacklogItem_number_key" ON "BacklogItem"("number");

CREATE INDEX IF NOT EXISTS "BacklogItem_appId_status_rank_idx" ON "BacklogItem"("appId", "status", "rank");

CREATE INDEX IF NOT EXISTS "BacklogItem_status_focusRank_idx" ON "BacklogItem"("status", "focusRank");

CREATE INDEX IF NOT EXISTS "BacklogItem_ownerId_status_idx" ON "BacklogItem"("ownerId", "status");

CREATE INDEX IF NOT EXISTS "BacklogItem_parentId_idx" ON "BacklogItem"("parentId");

CREATE INDEX IF NOT EXISTS "BacklogItem_createdById_idx" ON "BacklogItem"("createdById");

CREATE INDEX IF NOT EXISTS "BacklogItem_sourceRequestId_idx" ON "BacklogItem"("sourceRequestId");

CREATE INDEX IF NOT EXISTS "BacklogItemRelation_toId_idx" ON "BacklogItemRelation"("toId");

CREATE UNIQUE INDEX IF NOT EXISTS "BacklogItemRelation_fromId_toId_kind_key" ON "BacklogItemRelation"("fromId", "toId", "kind");

CREATE INDEX IF NOT EXISTS "BacklogLink_repoFullName_number_idx" ON "BacklogLink"("repoFullName", "number");

CREATE UNIQUE INDEX IF NOT EXISTS "BacklogLink_itemId_url_key" ON "BacklogLink"("itemId", "url");

CREATE INDEX IF NOT EXISTS "BacklogComment_itemId_createdAt_idx" ON "BacklogComment"("itemId", "createdAt");

CREATE INDEX IF NOT EXISTS "BacklogComment_parentId_idx" ON "BacklogComment"("parentId");

CREATE INDEX IF NOT EXISTS "BacklogComment_authorId_idx" ON "BacklogComment"("authorId");

CREATE INDEX IF NOT EXISTS "BacklogAttachment_itemId_idx" ON "BacklogAttachment"("itemId");

CREATE INDEX IF NOT EXISTS "BacklogAttachment_commentId_idx" ON "BacklogAttachment"("commentId");

CREATE INDEX IF NOT EXISTS "BacklogSubscriber_userId_idx" ON "BacklogSubscriber"("userId");

CREATE UNIQUE INDEX IF NOT EXISTS "BacklogSubscriber_itemId_userId_key" ON "BacklogSubscriber"("itemId", "userId");

CREATE INDEX IF NOT EXISTS "BacklogActivity_itemId_createdAt_idx" ON "BacklogActivity"("itemId", "createdAt");

CREATE INDEX IF NOT EXISTS "BacklogActivity_actorId_idx" ON "BacklogActivity"("actorId");

DO $$ BEGIN
  ALTER TABLE "BacklogApp"
      ADD CONSTRAINT "BacklogApp_familyId_fkey"
      FOREIGN KEY ("familyId") REFERENCES "BacklogFamily"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogItem"
      ADD CONSTRAINT "BacklogItem_appId_fkey"
      FOREIGN KEY ("appId") REFERENCES "BacklogApp"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogItem"
      ADD CONSTRAINT "BacklogItem_parentId_fkey"
      FOREIGN KEY ("parentId") REFERENCES "BacklogItem"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogItem"
      ADD CONSTRAINT "BacklogItem_ownerId_fkey"
      FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogItem"
      ADD CONSTRAINT "BacklogItem_createdById_fkey"
      FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogItemRelation"
      ADD CONSTRAINT "BacklogItemRelation_fromId_fkey"
      FOREIGN KEY ("fromId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogItemRelation"
      ADD CONSTRAINT "BacklogItemRelation_toId_fkey"
      FOREIGN KEY ("toId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogLink"
      ADD CONSTRAINT "BacklogLink_itemId_fkey"
      FOREIGN KEY ("itemId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogComment"
      ADD CONSTRAINT "BacklogComment_itemId_fkey"
      FOREIGN KEY ("itemId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogComment"
      ADD CONSTRAINT "BacklogComment_authorId_fkey"
      FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogComment"
      ADD CONSTRAINT "BacklogComment_parentId_fkey"
      FOREIGN KEY ("parentId") REFERENCES "BacklogComment"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogComment"
      ADD CONSTRAINT "BacklogComment_resolvedById_fkey"
      FOREIGN KEY ("resolvedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogAttachment"
      ADD CONSTRAINT "BacklogAttachment_itemId_fkey"
      FOREIGN KEY ("itemId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogAttachment"
      ADD CONSTRAINT "BacklogAttachment_commentId_fkey"
      FOREIGN KEY ("commentId") REFERENCES "BacklogComment"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogAttachment"
      ADD CONSTRAINT "BacklogAttachment_uploadedById_fkey"
      FOREIGN KEY ("uploadedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogSubscriber"
      ADD CONSTRAINT "BacklogSubscriber_itemId_fkey"
      FOREIGN KEY ("itemId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogSubscriber"
      ADD CONSTRAINT "BacklogSubscriber_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogActivity"
      ADD CONSTRAINT "BacklogActivity_itemId_fkey"
      FOREIGN KEY ("itemId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogActivity"
      ADD CONSTRAINT "BacklogActivity_actorId_fkey"
      FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
