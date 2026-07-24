-- Feature request tables — safe to run on production without touching other schemas.
-- Apply: npx prisma db execute --file scripts/add-feature-request-tables.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "FeatureRequestType" AS ENUM ('BUG_FIX', 'SMALL_FEATURE', 'BIG_FEATURE');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "FeatureRequestStatus" AS ENUM ('PENDING', 'IN_PROGRESS', 'RELEASED', 'REJECTED', 'DUPLICATE');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "FeatureRequest" (
  "id" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "type" "FeatureRequestType" NOT NULL,
  "status" "FeatureRequestStatus" NOT NULL DEFAULT 'PENDING',
  "relatedApps" TEXT[] NOT NULL,
  "authorId" TEXT NOT NULL,
  "attachmentKey" TEXT,
  "attachmentName" TEXT,
  "attachmentMime" TEXT,
  "canonicalId" TEXT,
  "voteCount" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "FeatureRequest_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FeatureRequestVote" (
  "id" TEXT NOT NULL,
  "requestId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "locked" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "FeatureRequestVote_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "FeatureRequest_status_voteCount_idx" ON "FeatureRequest"("status", "voteCount");
CREATE INDEX IF NOT EXISTS "FeatureRequest_createdAt_idx" ON "FeatureRequest"("createdAt");
CREATE INDEX IF NOT EXISTS "FeatureRequest_type_idx" ON "FeatureRequest"("type");
CREATE INDEX IF NOT EXISTS "FeatureRequest_authorId_idx" ON "FeatureRequest"("authorId");
CREATE INDEX IF NOT EXISTS "FeatureRequest_canonicalId_idx" ON "FeatureRequest"("canonicalId");
CREATE INDEX IF NOT EXISTS "FeatureRequestVote_userId_idx" ON "FeatureRequestVote"("userId");

DO $$ BEGIN
  ALTER TABLE "FeatureRequest" ADD CONSTRAINT "FeatureRequest_authorId_fkey"
    FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FeatureRequest" ADD CONSTRAINT "FeatureRequest_canonicalId_fkey"
    FOREIGN KEY ("canonicalId") REFERENCES "FeatureRequest"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FeatureRequestVote" ADD CONSTRAINT "FeatureRequestVote_requestId_fkey"
    FOREIGN KEY ("requestId") REFERENCES "FeatureRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FeatureRequestVote" ADD CONSTRAINT "FeatureRequestVote_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FeatureRequestVote" ADD CONSTRAINT "FeatureRequestVote_requestId_userId_key"
    UNIQUE ("requestId", "userId");
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
