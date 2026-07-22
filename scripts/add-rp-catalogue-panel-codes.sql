-- RP spare-parts DB catalogue, panel options, and shared panel codes.
-- Apply: npx prisma db execute --schema prisma/schema.prisma --file scripts/add-rp-catalogue-panel-codes.sql

-- MrpBoothElement.code (shared with FactoryElement.code)
ALTER TABLE "MrpBoothElement" ADD COLUMN IF NOT EXISTS "code" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "MrpBoothElement_boothModelId_code_key"
  ON "MrpBoothElement"("boothModelId", "code");
CREATE INDEX IF NOT EXISTS "MrpBoothElement_code_idx" ON "MrpBoothElement"("code");

-- RpLineItem.panelCode
ALTER TABLE "rp_line_items" ADD COLUMN IF NOT EXISTS "panel_code" TEXT;
CREATE INDEX IF NOT EXISTS "rp_line_items_panel_code_idx" ON "rp_line_items"("panel_code");

-- RpPanelMrpMap.panelCode
ALTER TABLE "rp_panel_mrp_maps" ADD COLUMN IF NOT EXISTS "panel_code" TEXT;
CREATE INDEX IF NOT EXISTS "rp_panel_mrp_maps_panel_code_idx" ON "rp_panel_mrp_maps"("panel_code");

CREATE TABLE IF NOT EXISTS "rp_spare_parts" (
  "id" TEXT NOT NULL,
  "code" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "category" TEXT NOT NULL,
  "subcategory" TEXT,
  "booth" TEXT,
  "photo_url" TEXT,
  "image_file_id" TEXT,
  "standard_partner" BOOLEAN NOT NULL DEFAULT false,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "rp_spare_parts_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "rp_spare_parts_code_key" ON "rp_spare_parts"("code");
CREATE INDEX IF NOT EXISTS "rp_spare_parts_category_idx" ON "rp_spare_parts"("category");
CREATE INDEX IF NOT EXISTS "rp_spare_parts_is_active_idx" ON "rp_spare_parts"("is_active");

CREATE TABLE IF NOT EXISTS "rp_panel_options" (
  "id" TEXT NOT NULL,
  "booth_model_code" TEXT NOT NULL,
  "panel_code" TEXT NOT NULL,
  "label_bg" TEXT NOT NULL,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "rp_panel_options_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "rp_panel_options_booth_model_code_panel_code_key"
  ON "rp_panel_options"("booth_model_code", "panel_code");
CREATE INDEX IF NOT EXISTS "rp_panel_options_booth_model_code_idx" ON "rp_panel_options"("booth_model_code");
CREATE INDEX IF NOT EXISTS "rp_panel_options_panel_code_idx" ON "rp_panel_options"("panel_code");
CREATE INDEX IF NOT EXISTS "rp_panel_options_is_active_idx" ON "rp_panel_options"("is_active");
