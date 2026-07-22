-- RP ↔ MRP material / panel recipe maps + line-item deduction idempotency.
-- Apply via: npx prisma db execute --file scripts/add-rp-mrp-maps.sql
-- Or: npm run db:push after schema update.

ALTER TABLE "rp_line_items"
  ADD COLUMN IF NOT EXISTS "materials_deducted_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "materials_deduction_error" TEXT;

CREATE INDEX IF NOT EXISTS "rp_line_items_materials_deducted_at_idx"
  ON "rp_line_items"("materials_deducted_at");

CREATE TABLE IF NOT EXISTS "rp_part_mrp_maps" (
  "id" TEXT NOT NULL,
  "part_rp_code" TEXT NOT NULL,
  "mrp_material_id" TEXT NOT NULL,
  "notes" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "rp_part_mrp_maps_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "rp_part_mrp_maps_part_rp_code_key"
  ON "rp_part_mrp_maps"("part_rp_code");

CREATE INDEX IF NOT EXISTS "rp_part_mrp_maps_mrp_material_id_idx"
  ON "rp_part_mrp_maps"("mrp_material_id");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'rp_part_mrp_maps_mrp_material_id_fkey'
  ) THEN
    ALTER TABLE "rp_part_mrp_maps"
      ADD CONSTRAINT "rp_part_mrp_maps_mrp_material_id_fkey"
      FOREIGN KEY ("mrp_material_id") REFERENCES "MrpMaterial"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "rp_panel_mrp_maps" (
  "id" TEXT NOT NULL,
  "booth_model_name" TEXT NOT NULL,
  "rp_panel_name" TEXT NOT NULL,
  "booth_element_id" TEXT NOT NULL,
  "notes" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "rp_panel_mrp_maps_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "rp_panel_mrp_maps_booth_model_name_rp_panel_name_key"
  ON "rp_panel_mrp_maps"("booth_model_name", "rp_panel_name");

CREATE INDEX IF NOT EXISTS "rp_panel_mrp_maps_booth_element_id_idx"
  ON "rp_panel_mrp_maps"("booth_element_id");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'rp_panel_mrp_maps_booth_element_id_fkey'
  ) THEN
    ALTER TABLE "rp_panel_mrp_maps"
      ADD CONSTRAINT "rp_panel_mrp_maps_booth_element_id_fkey"
      FOREIGN KEY ("booth_element_id") REFERENCES "MrpBoothElement"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;
