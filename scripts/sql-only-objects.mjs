#!/usr/bin/env node
// SQL-only objects: what the shared database holds that prisma/schema.prisma cannot
// declare, so `prisma migrate diff` never sees them. CHECK constraints, partial and
// expression indexes, triggers, functions and sequences. prisma/sql-only-objects.json
// lists every one of them (kind, table, name, definition as PostgreSQL prints it).
//
//   node scripts/sql-only-objects.mjs sql       print the one SELECT that lists them
//   node scripts/sql-only-objects.mjs dump      print the objects of DATABASE_URL as an inventory
//   node scripts/sql-only-objects.mjs compare   DATABASE_URL against the inventory, both ways
//   node scripts/sql-only-objects.mjs format    rewrite the inventory sorted, one object per line
//   node scripts/sql-only-objects.mjs coverage  (replay check) what the replayed scripts created is in
//                                               the inventory; every other entry is defined by a script
//   node scripts/sql-only-objects.mjs seed      (replay check, localhost only) create the inventory's
//                                               objects that DATABASE_URL does not have
//
// Options: --rows <file> reads a saved result of the SELECT instead of a database (dump,
// compare); --inventory <file> uses another inventory file (compare, seed).
// Database reads run in a read-only transaction. Production is read through the
// workspace's guarded helper, never through DATABASE_URL here; the commands are in
// docs/data-model.md, "SQL-only objects". scripts/verify-sql-replay.sh runs the checks in CI.
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const INVENTORY = join(root, "prisma", "sql-only-objects.json");
const KINDS = ["check", "partial-index", "expression-index", "trigger", "function", "sequence"];
const ABOUT =
  "Every object in the shared database that prisma/schema.prisma cannot declare: CHECK constraints, " +
  "partial and expression indexes, triggers, functions and sequences, with the definition PostgreSQL " +
  "prints. scripts/verify-sql-replay.sh (CI) fails when a script adds, changes or drops one without " +
  "this file. How to add one and how to compare with production: docs/data-model.md, SQL-only objects.";

// One statement without semicolons or comments, so the workspace's read-only production
// helper accepts it as it is. Only the public schema (neon_auth belongs to Neon Auth).
// Functions that belong to an extension are left out, and so are the
// prisma_dev_wal_capture triggers a local `prisma dev` server puts on every table.
const QUERY = `SELECT json_agg(json_build_object('kind', o.kind, 'table', o.tbl, 'name', o.name, 'definition', o.definition)) AS objects
FROM (
  SELECT 'check' AS kind, c.relname::text AS tbl, con.conname::text AS name, pg_get_constraintdef(con.oid) AS definition
  FROM pg_constraint con
  JOIN pg_class c ON c.oid = con.conrelid
  WHERE con.contype::text = 'c' AND c.relnamespace = 'public'::regnamespace
  UNION ALL
  SELECT CASE WHEN x.indpred IS NOT NULL THEN 'partial-index' ELSE 'expression-index' END, c.relname::text, i.relname::text,
         pg_get_indexdef(x.indexrelid) || CASE WHEN x.indisvalid THEN '' ELSE ' -- INVALID' END
  FROM pg_index x
  JOIN pg_class i ON i.oid = x.indexrelid
  JOIN pg_class c ON c.oid = x.indrelid
  WHERE c.relnamespace = 'public'::regnamespace AND (x.indpred IS NOT NULL OR x.indexprs IS NOT NULL)
  UNION ALL
  SELECT 'trigger', c.relname::text, t.tgname::text,
         pg_get_triggerdef(t.oid) || CASE WHEN t.tgenabled::text = 'O' THEN '' ELSE ' -- ENABLED ' || t.tgenabled::text END
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace AND t.tgname::text <> 'prisma_dev_wal_capture'
  UNION ALL
  SELECT 'function', '', p.proname::text || '(' || pg_get_function_identity_arguments(p.oid) || ')', rtrim(pg_get_functiondef(p.oid), E'\\n')
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND p.prokind::text <> 'a'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype::text = 'e')
  UNION ALL
  SELECT 'sequence', coalesce(own.tbl, ''), s.relname::text,
         'AS ' || format_type(q.seqtypid, NULL) || ' START WITH ' || q.seqstart || ' INCREMENT BY ' || q.seqincrement
         || ' MINVALUE ' || q.seqmin || ' MAXVALUE ' || q.seqmax || ' CACHE ' || q.seqcache
         || CASE WHEN q.seqcycle THEN ' CYCLE' ELSE ' NO CYCLE' END || ' OWNED BY ' || coalesce(own.col, 'NONE')
  FROM pg_sequence q
  JOIN pg_class s ON s.oid = q.seqrelid
  LEFT JOIN LATERAL (
    SELECT oc.relname::text AS tbl, quote_ident(oc.relname) || '.' || quote_ident(a.attname) AS col
    FROM pg_depend d
    JOIN pg_class oc ON oc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
    WHERE d.classid = 'pg_class'::regclass AND d.objid = s.oid AND d.refclassid = 'pg_class'::regclass
      AND d.deptype::text IN ('a', 'i')
    LIMIT 1
  ) own ON true
  WHERE s.relnamespace = 'public'::regnamespace
) o`;

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

const [command, ...rest] = process.argv.slice(2);
const options = {};
for (let i = 0; i < rest.length; i += 2) {
  if (!["--rows", "--inventory"].includes(rest[i]) || !rest[i + 1]) fail(`unknown or incomplete option ${rest[i]}`);
  options[rest[i].slice(2)] = rest[i + 1];
}
const inventoryPath = options.inventory ?? INVENTORY;
const shown = (path) => relative(process.cwd(), path) || path;

const key = (o) => `${o.kind}\u0000${o.table}\u0000${o.name}`;
const label = (o) => `${o.kind} ${o.table ? `${o.table}.` : ""}${o.name}`;

// Accepts the SELECT's result ([{ objects: [...] }]), an inventory ({ objects: [...] }) or a bare list.
function normalise(input, source) {
  const list = Array.isArray(input) ? (input.length === 1 && "objects" in input[0] ? input[0].objects : input) : input?.objects;
  if (list === null) return [];
  if (!Array.isArray(list)) fail(`${source}: expected a list of objects`);
  const objects = list.map((o) => ({
    kind: o.kind,
    table: o.table,
    name: o.name,
    definition: Array.isArray(o.definition) ? o.definition.join("\n") : o.definition,
  }));
  const seen = new Set();
  for (const o of objects) {
    if (!KINDS.includes(o.kind) || [o.table, o.name, o.definition].some((v) => typeof v !== "string") || !o.name || !o.definition)
      fail(`${source}: not a SQL-only object: ${JSON.stringify(o)}`);
    if (seen.has(key(o))) fail(`${source}: ${label(o)} is listed twice`);
    seen.add(key(o));
  }
  const order = (o) => [KINDS.indexOf(o.kind), o.table, o.name];
  return objects.sort((a, b) => {
    const [x, y] = [order(a), order(b)];
    for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
    return 0;
  });
}

// One object per line; a definition of several lines (a function) is a list of its lines.
function line(o) {
  const head = `{"kind": ${JSON.stringify(o.kind)}, "table": ${JSON.stringify(o.table)}, "name": ${JSON.stringify(o.name)}, "definition": `;
  if (!o.definition.includes("\n")) return `    ${head}${JSON.stringify(o.definition)}}`;
  return `    ${head}[\n${o.definition.split("\n").map((l) => `      ${JSON.stringify(l)}`).join(",\n")}\n    ]}`;
}
const format = (objects) => `{\n  "about": ${JSON.stringify(ABOUT)},\n  "objects": [\n${objects.map(line).join(",\n")}\n  ]\n}\n`;

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`cannot read ${shown(path)}: ${error.message}`);
  }
}

function readInventory(path = inventoryPath) {
  const objects = normalise(readJson(path), shown(path));
  if (readFileSync(path, "utf8") !== format(objects))
    fail(`${shown(path)} is not sorted and formatted: run node scripts/sql-only-objects.mjs format`);
  return objects;
}

const isLocal = (url) => /@(127\.0\.0\.1|localhost)[:/]/.test(url);

function connect() {
  const url = process.env.DATABASE_URL;
  if (!url) fail("DATABASE_URL is not set");
  // pgbouncer mode keeps no named prepared statements, so nothing of this session is left
  // behind on a local server that shares one session between clients (`prisma dev`).
  const separator = url.includes("?") ? "&" : "?";
  try {
    const { PrismaClient } = createRequire(import.meta.url)("@prisma/client");
    return new PrismaClient({ datasources: { db: { url: url.includes("pgbouncer=") ? url : `${url}${separator}pgbouncer=true` } } });
  } catch {
    fail("the Prisma client is missing: run npm ci (or npx prisma generate) in the repository");
  }
}

async function withDatabase(work) {
  const prisma = connect();
  try {
    return await work(prisma);
  } catch (error) {
    fail(String(error?.meta?.message ?? error?.message ?? error).replace(/postgres(ql)?:\/\/\S+/g, "<database url>"));
  } finally {
    await prisma.$disconnect();
  }
}

async function readObjects(prisma) {
  const [, rows] = await prisma.$transaction([prisma.$executeRawUnsafe("SET TRANSACTION READ ONLY"), prisma.$queryRawUnsafe(QUERY)]);
  return normalise(rows, "the database");
}

const actual = () => (options.rows ? normalise(readJson(options.rows), shown(options.rows)) : withDatabase(readObjects));

const counts = (objects) =>
  KINDS.map((kind) => [objects.filter((o) => o.kind === kind).length, kind])
    .filter(([n]) => n)
    .map(([n, kind]) => `${n} ${kind}`)
    .join(", ") || "none";

// Prints what differs and returns how many objects do. `subset` ignores inventory entries the source lacks.
function differences(found, inventory, source, { subset = false } = {}) {
  const have = new Map(found.map((o) => [key(o), o]));
  const want = new Map(inventory.map((o) => [key(o), o]));
  const extra = found.filter((o) => !want.has(key(o)));
  const missing = subset ? [] : inventory.filter((o) => !have.has(key(o)));
  const changed = found.filter((o) => want.has(key(o)) && want.get(key(o)).definition !== o.definition);
  if (extra.length) {
    console.log(`In ${source} but not in the inventory (${extra.length}). To record them, add these lines to "objects":`);
    for (const o of extra) console.log(`${line(o)},`);
  }
  if (missing.length) {
    console.log(`In the inventory but not in ${source} (${missing.length}):`);
    for (const o of missing) console.log(`    ${label(o)}`);
  }
  if (changed.length) {
    console.log(`Defined differently in ${source} (${changed.length}). To record its definition, replace each object's line with:`);
    for (const o of changed) console.log(`${line(o)},\n      (the inventory has: ${want.get(key(o)).definition})`);
  }
  return extra.length + missing.length + changed.length;
}

// ---- reading the scripts: which file defines an object ---------------------------------

const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const named = (name) => `(?:public\\.)?"?${escape(name)}"?`;

// The comma-separated entries of every CREATE TABLE statement for `table`.
function tableEntries(sql, table) {
  const entries = [];
  const start = new RegExp(`CREATE\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?${named(table)}\\s*\\(`, "gi");
  for (let match; (match = start.exec(sql)); ) {
    let depth = 1;
    let from = start.lastIndex;
    let quoted = false;
    for (let i = from; i < sql.length && depth > 0; i++) {
      const c = sql[i];
      if (quoted) quoted = c !== "'";
      else if (c === "'") quoted = true;
      else if (c === "(") depth++;
      else if (c === ")" && --depth === 0) entries.push(sql.slice(from, i).trim());
      else if (c === "," && depth === 1) {
        entries.push(sql.slice(from, i).trim());
        from = i + 1;
      }
    }
  }
  return entries;
}

function defines(sql, o) {
  const has = (pattern) => new RegExp(pattern, "i").test(sql);
  if (o.kind === "function") return has(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?(?:FUNCTION|PROCEDURE)\\s+${named(o.name.replace(/\(.*$/, ""))}\\s*\\(`);
  if (o.kind === "trigger") return has(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?(?:CONSTRAINT\\s+)?TRIGGER\\s+"?${escape(o.name)}"?\\s[^;]*?\\sON\\s+${named(o.table)}[\\s;]`);
  if (o.kind === "sequence") return has(`CREATE\\s+SEQUENCE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?${named(o.name)}[\\s;]`);
  if (o.kind !== "check") return has(`CREATE\\s+(?:UNIQUE\\s+)?INDEX\\s+(?:CONCURRENTLY\\s+)?(?:IF\\s+NOT\\s+EXISTS\\s+)?"?${escape(o.name)}"?\\s+ON\\s`);
  if (has(`CONSTRAINT\\s+"?${escape(o.name)}"?\\s+CHECK\\b`)) return true;
  // An unnamed CHECK inside CREATE TABLE gets PostgreSQL's own name: <table>_<column>_check
  // when it reads one column, <table>_check, <table>_check1, ... when it reads several.
  const auto = o.name.startsWith(`${o.table}_`) && /^(?:(.+)_)?check(\d*)$/.exec(o.name.slice(o.table.length + 1));
  if (!auto) return false;
  const [, column, number] = auto;
  const entries = tableEntries(sql, o.table);
  const tableLevel = entries.filter((entry) => /^CHECK\b/i.test(entry));
  if (!column) return tableLevel.length > Number(number || 0);
  const mentions = new RegExp(`(^|[^A-Za-z0-9_])${escape(column)}([^A-Za-z0-9_]|$)`);
  const declares = new RegExp(`^"?${escape(column)}"?\\s`);
  return tableLevel.some((entry) => mentions.test(entry)) || entries.some((entry) => declares.test(entry) && /\bCHECK\s*\(/i.test(entry) && !/\bCONSTRAINT\b/i.test(entry));
}

function scriptsDefining(objects) {
  const directory = join(root, "scripts");
  const scripts = readdirSync(directory)
    .filter((file) => file.endsWith(".sql"))
    .sort()
    .map((file) => ({ file: `scripts/${file}`, sql: readFileSync(join(directory, file), "utf8").replace(/\/\*[\s\S]*?\*\//g, " ").replace(/--[^\n]*/g, "") }));
  return new Map(objects.map((o) => [key(o), scripts.filter((s) => defines(s.sql, o)).map((s) => s.file)]));
}

// ---- commands ----------------------------------------------------------------------------

if (command === "sql") {
  console.log(QUERY);
} else if (command === "dump") {
  process.stdout.write(format(await actual()));
} else if (command === "format") {
  const objects = normalise(readJson(inventoryPath), shown(inventoryPath));
  writeFileSync(inventoryPath, format(objects));
  console.log(`OK   ${shown(inventoryPath)}: ${objects.length} objects (${counts(objects)})`);
} else if (command === "compare") {
  const inventory = readInventory();
  const found = await actual();
  const source = options.rows ? shown(options.rows) : "the database";
  if (differences(found, inventory, source)) fail(`${source} and ${shown(inventoryPath)} differ (above)`);
  console.log(`OK   ${source} holds exactly the ${inventory.length} objects of ${shown(inventoryPath)} (${counts(inventory)})`);
} else if (command === "coverage") {
  const inventory = readInventory();
  const created = await withDatabase(readObjects);
  if (differences(created, inventory, "the replayed database", { subset: true }))
    fail(`the replayed scripts create SQL-only objects that ${shown(inventoryPath)} does not record as they are (above)`);
  console.log(`OK   ${created.length} of the ${inventory.length} objects are created by the replayed scripts, exactly as recorded (${counts(created)})`);
  const have = new Set(created.map(key));
  const others = inventory.filter((o) => !have.has(key(o)));
  const definedBy = scriptsDefining(others);
  const orphans = others.filter((o) => !definedBy.get(key(o)).length);
  if (orphans.length) {
    for (const o of orphans) console.log(`    ${label(o)}`);
    fail("no file in scripts/ defines the objects above: declare each in an idempotent script and list it in REPLAY");
  }
  if (others.length) {
    console.log(`OK   the other ${others.length} are defined by scripts that are not replayed (found by reading them, not by running them):`);
    const perScript = new Map();
    for (const o of others) for (const file of definedBy.get(key(o))) perScript.set(file, (perScript.get(file) ?? 0) + 1);
    for (const [file, n] of [...perScript].sort()) console.log(`       ${String(n).padStart(3)} ${file}`);
  }
} else if (command === "seed") {
  if (!isLocal(process.env.DATABASE_URL ?? "")) fail("seed writes: it refuses a DATABASE_URL that is not on localhost or 127.0.0.1");
  const inventory = normalise(readJson(inventoryPath), shown(inventoryPath));
  const quote = (name) => `"${name.replace(/"/g, '""')}"`;
  const statement = (o) =>
    o.kind === "check" ? `ALTER TABLE public.${quote(o.table)} ADD CONSTRAINT ${quote(o.name)} ${o.definition}`
    : o.kind === "sequence" ? `CREATE SEQUENCE public.${quote(o.name)} ${o.definition}`
    : o.definition;
  const created = await withDatabase(async (prisma) => {
    const have = new Set((await readObjects(prisma)).map(key));
    // Functions before the triggers that call them.
    const missing = ["sequence", "function", "check", "partial-index", "expression-index", "trigger"]
      .flatMap((kind) => inventory.filter((o) => o.kind === kind && !have.has(key(o))));
    for (const o of missing) {
      try {
        await prisma.$executeRawUnsafe(statement(o));
      } catch (error) {
        throw new Error(`cannot create ${label(o)} from its definition: ${error?.meta?.message ?? error?.message ?? error}`);
      }
    }
    return missing;
  });
  console.log(`OK   created ${created.length} of the ${inventory.length} recorded objects (${counts(created)}); the others were there`);
} else {
  console.error("usage: node scripts/sql-only-objects.mjs sql | dump | compare | format | coverage | seed  [--rows <file>] [--inventory <file>]");
  process.exit(2);
}
