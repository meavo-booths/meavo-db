/**
 * Apply MRP electric + recipe versioning schema additions to this repo's schema.
 * Run from meavo-db root: node scripts/apply-mrp-patches.cjs
 */
const fs = require("fs");
const path = require("path");

const schemaPath = path.join(__dirname, "..", "prisma", "schema.prisma");
let schema = fs.readFileSync(schemaPath, "utf8");

function fail(msg) {
  console.error(`[apply-mrp-patches] ${msg}`);
  process.exit(1);
}

// --- Electric recipes (skip if present) ---
if (!schema.includes("model MrpElectricModule")) {
  const boothNeedle = `  elements             MrpBoothElement[]
  manufacturingBatches MrpManufacturingBatch[]
  exceptionScopes      MrpRecipeExceptionScope[]
}`;
  if (!schema.includes(boothNeedle)) fail("MrpBoothModel relations anchor missing");
  schema = schema.replace(
    boothNeedle,
    `  elements             MrpBoothElement[]
  manufacturingBatches MrpManufacturingBatch[]
  exceptionScopes      MrpRecipeExceptionScope[]
  electricAssemblies   MrpElectricAssembly[]
}`,
  );

  const materialNeedle = `  inventoryCounts      MrpInventoryCount[]
  rpPartMaps           RpPartMrpMap[]
`;
  if (!schema.includes(materialNeedle)) fail("MrpMaterial relations anchor missing");
  schema = schema.replace(
    materialNeedle,
    `  inventoryCounts      MrpInventoryCount[]
  rpPartMaps           RpPartMrpMap[]
  electricModuleLines  MrpElectricModuleLine[]
`,
  );

  const insertNeedle = `/// Row from master sheet Статус на партиди (synced from Google Sheets).
model MrpManufacturingBatch {`;
  if (!schema.includes(insertNeedle)) fail("MrpManufacturingBatch marker missing");

  const electricModels = `
/// Reusable electric sub-recipe (loom / kit). Not a packing-panel element.
model MrpElectricModule {
  id        String   @id @default(cuid())
  code      String   @unique
  /// Manufacturing / drawing number for the module as a whole.
  partCode  String   @unique
  name      String
  notes     String?
  sortOrder Int      @default(0)
  isActive  Boolean  @default(true)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  lines         MrpElectricModuleLine[]
  assemblyLines MrpElectricAssemblyLine[]
}

/// Materials that make up one electric module.
model MrpElectricModuleLine {
  id         String   @id @default(cuid())
  moduleId   String
  materialId String
  /// null = all markets; default = non-US; US = US only.
  market     String?
  quantity   Decimal  @db.Decimal(18, 4)
  createdAt  DateTime @default(now())

  module   MrpElectricModule @relation(fields: [moduleId], references: [id], onDelete: Cascade)
  material MrpMaterial       @relation(fields: [materialId], references: [id], onDelete: Restrict)

  @@unique([moduleId, market, materialId])
  @@index([materialId])
}

/// Booth-level electric recipe composed only of modules (no loose materials).
model MrpElectricAssembly {
  id           String   @id @default(cuid())
  code         String   @unique
  name         String
  boothModelId String
  /// Optional station: ceiling | table | ports | full
  kind         String?
  notes        String?
  sortOrder    Int      @default(0)
  isActive     Boolean  @default(true)
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt

  boothModel            MrpBoothModel              @relation(fields: [boothModelId], references: [id], onDelete: Cascade)
  lines                 MrpElectricAssemblyLine[]
  versionElectricRefs   MrpRecipeVersionElectric[]

  @@index([boothModelId])
}

model MrpElectricAssemblyLine {
  id         String   @id @default(cuid())
  assemblyId String
  moduleId   String
  quantity   Decimal  @db.Decimal(18, 4)
  createdAt  DateTime @default(now())

  assembly MrpElectricAssembly @relation(fields: [assemblyId], references: [id], onDelete: Cascade)
  module   MrpElectricModule   @relation(fields: [moduleId], references: [id], onDelete: Restrict)

  @@unique([assemblyId, moduleId])
  @@index([moduleId])
}

`;

  schema = schema.replace(insertNeedle, `${electricModels}${insertNeedle}`);
  console.log("[apply-mrp-patches] added electric models");
} else {
  console.log("[apply-mrp-patches] electric models already present");
}

// --- Recipe versioning (skip if present) ---
if (!schema.includes("model MrpRecipeVersion")) {
  const enums = `
enum MrpRecipeVersionStatus {
  draft
  ready
  archived
}

enum MrpRecipeVersionPanelChangeType {
  unchanged
  recipe_changed
  added
  removed
  renamed
}

enum MrpRecipeVersionElectricParityMode {
  same_as_source
  different
}
`;

  const enumNeedle = `enum MrpRecipeExceptionStatus {`;
  if (!schema.includes(enumNeedle)) fail("enum anchor missing");
  schema = schema.replace(enumNeedle, `${enums}\n${enumNeedle}`);

  const boothNeedle2 = `  exceptionScopes      MrpRecipeExceptionScope[]
  electricAssemblies   MrpElectricAssembly[]
}`;
  const boothNeedle1 = `  exceptionScopes      MrpRecipeExceptionScope[]
}`;
  if (schema.includes(boothNeedle2)) {
    schema = schema.replace(
      boothNeedle2,
      `  exceptionScopes      MrpRecipeExceptionScope[]
  electricAssemblies   MrpElectricAssembly[]
  recipeVersions       MrpRecipeVersion[]
}`,
    );
  } else if (schema.includes(boothNeedle1)) {
    schema = schema.replace(
      boothNeedle1,
      `  exceptionScopes      MrpRecipeExceptionScope[]
  recipeVersions       MrpRecipeVersion[]
}`,
    );
  } else {
    fail("MrpBoothModel recipeVersions anchor missing");
  }

  schema = schema.replace(
    `model MrpElementBomLine {
  id             String   @id @default(cuid())
  boothElementId String
  materialId     String`,
    `model MrpElementBomLine {
  id              String   @id @default(cuid())
  recipeVersionId String?
  boothElementId  String
  materialId      String`,
  );

  schema = schema.replace(
    `  boothElement MrpBoothElement @relation(fields: [boothElementId], references: [id], onDelete: Cascade)
  material     MrpMaterial     @relation(fields: [materialId], references: [id], onDelete: Restrict)

  @@unique([boothElementId, colour, market, materialId])
}`,
    `  recipeVersion MrpRecipeVersion? @relation(fields: [recipeVersionId], references: [id], onDelete: Cascade)
  boothElement  MrpBoothElement    @relation(fields: [boothElementId], references: [id], onDelete: Cascade)
  material      MrpMaterial        @relation(fields: [materialId], references: [id], onDelete: Restrict)

  @@unique([recipeVersionId, boothElementId, colour, market, materialId])
  @@index([recipeVersionId])
}`,
  );

  schema = schema.replace(
    `  batchSpreadsheetId String?
  /// Business DealID`,
    `  batchSpreadsheetId String?
  recipeVersionId      String?
  sheetRecipeVersion   String?
  /// Business DealID`,
  );

  schema = schema.replace(
    `  boothModel     MrpBoothModel?                 @relation(fields: [boothModelId], references: [id], onDelete: SetNull)
  warehouse      MrpWarehouse?                  @relation(fields: [warehouseId], references: [id], onDelete: SetNull)
  units          MrpBatchUnit[]
  exceptionLinks MrpRecipeExceptionBatchLink[]`,
    `  boothModel        MrpBoothModel?                 @relation(fields: [boothModelId], references: [id], onDelete: SetNull)
  warehouse         MrpWarehouse?                  @relation(fields: [warehouseId], references: [id], onDelete: SetNull)
  recipeVersion     MrpRecipeVersion?              @relation(fields: [recipeVersionId], references: [id], onDelete: SetNull)
  units             MrpBatchUnit[]
  exceptionLinks    MrpRecipeExceptionBatchLink[]
  versionBatchLinks MrpRecipeVersionBatchLink[]`,
  );

  schema = schema.replace(
    `  mrpRecipeExceptionsCreated MrpRecipeException[] @relation("MrpRecipeExceptionCreator")`,
    `  mrpRecipeExceptionsCreated MrpRecipeException[] @relation("MrpRecipeExceptionCreator")
  mrpRecipeVersionsCreated   MrpRecipeVersion[]   @relation("MrpRecipeVersionCreator")`,
  );

  const versionModels = `
/// Published recipe snapshot for a booth model (V1.1, V1.2, Legacy, …).
model MrpRecipeVersion {
  id              String                   @id @default(cuid())
  boothModelId    String
  label           String
  status          MrpRecipeVersionStatus   @default(draft)
  notes           String?
  isDefault       Boolean                  @default(false)
  sourceVersionId String?
  createdById     String?
  createdAt       DateTime                 @default(now())
  updatedAt       DateTime                 @updatedAt

  boothModel        MrpBoothModel                  @relation(fields: [boothModelId], references: [id], onDelete: Cascade)
  sourceVersion     MrpRecipeVersion?              @relation("MrpRecipeVersionSource", fields: [sourceVersionId], references: [id], onDelete: SetNull)
  derivedVersions   MrpRecipeVersion[]             @relation("MrpRecipeVersionSource")
  createdBy         User?                          @relation("MrpRecipeVersionCreator", fields: [createdById], references: [id], onDelete: SetNull)
  panels            MrpRecipeVersionPanel[]
  bomLines          MrpElementBomLine[]
  electricSnapshots MrpRecipeVersionElectric[]
  batches           MrpManufacturingBatch[]
  batchLinks        MrpRecipeVersionBatchLink[]

  @@unique([boothModelId, label])
  @@index([boothModelId, status])
  @@index([boothModelId, isDefault])
}

/// Panel checklist row scoped to one recipe version.
model MrpRecipeVersionPanel {
  id                     String                           @id @default(cuid())
  recipeVersionId        String
  changeType             MrpRecipeVersionPanelChangeType  @default(unchanged)
  boothElementId         String?
  sourcePanelId          String?
  sheetHeader            String
  simpleName             String
  sortOrder              Int                              @default(0)
  isActive               Boolean                          @default(true)
  recipeCopiedFromSource Boolean                          @default(false)
  createdAt              DateTime                         @default(now())

  recipeVersion MrpRecipeVersion        @relation(fields: [recipeVersionId], references: [id], onDelete: Cascade)
  boothElement  MrpBoothElement?        @relation(fields: [boothElementId], references: [id], onDelete: SetNull)
  sourcePanel   MrpRecipeVersionPanel?  @relation("MrpRecipeVersionPanelSource", fields: [sourcePanelId], references: [id], onDelete: SetNull)
  derivedPanels MrpRecipeVersionPanel[] @relation("MrpRecipeVersionPanelSource")

  @@unique([recipeVersionId, sheetHeader])
  @@unique([recipeVersionId, simpleName])
  @@index([boothElementId])
}

/// Frozen electric assembly choice per kind for a recipe version.
model MrpRecipeVersionElectric {
  id               String                               @id @default(cuid())
  recipeVersionId  String
  kind             String
  parityMode       MrpRecipeVersionElectricParityMode
  sourceAssemblyId String?
  /// JSON: [{ moduleCode, quantity }] frozen at publish.
  moduleSnapshot   Json?
  createdAt        DateTime                             @default(now())

  recipeVersion  MrpRecipeVersion     @relation(fields: [recipeVersionId], references: [id], onDelete: Cascade)
  sourceAssembly MrpElectricAssembly? @relation(fields: [sourceAssemblyId], references: [id], onDelete: SetNull)

  @@unique([recipeVersionId, kind])
}

/// Explicit batch → version assignment (coverage rules).
model MrpRecipeVersionBatchLink {
  id                   String   @id @default(cuid())
  recipeVersionId      String
  manufacturingBatchId String?
  batchLabel           String?
  createdAt            DateTime @default(now())

  recipeVersion      MrpRecipeVersion       @relation(fields: [recipeVersionId], references: [id], onDelete: Cascade)
  manufacturingBatch MrpManufacturingBatch? @relation(fields: [manufacturingBatchId], references: [id], onDelete: SetNull)

  @@index([recipeVersionId])
  @@index([manufacturingBatchId])
  @@index([batchLabel])
}

`;

  const insertNeedle = `/// Row from master sheet Статус на партиди (synced from Google Sheets).
model MrpManufacturingBatch {`;
  schema = schema.replace(insertNeedle, `${versionModels}${insertNeedle}`);

  schema = schema.replace(
    `  rpPanelMaps       RpPanelMrpMap[]

  @@unique([boothModelId, sheetHeader])`,
    `  rpPanelMaps       RpPanelMrpMap[]
  versionPanels     MrpRecipeVersionPanel[]

  @@unique([boothModelId, sheetHeader])`,
  );

  console.log("[apply-mrp-patches] added recipe versioning models");
} else {
  console.log("[apply-mrp-patches] recipe versioning already present");
}

fs.writeFileSync(schemaPath, schema);
console.log("[apply-mrp-patches] schema updated");
