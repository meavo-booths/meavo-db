# Development and staging environments

Read `RELEASE_POLICY.md` before release, deployment, environment, schema or package operations. These instructions describe what to verify; they do not assert that a particular provider setting is currently enabled.

## Before a push or build

Inspect Git deployment triggers, install/build scripts, and the actual target environment. A documentation-only push can still start a build; some MEAVO builds run SQL, backfills or external-service code. Do not start those writes until their non-production destinations are verified. Do not change deployment triggers or credentials silently to make a build pass.

## Database and local development

Preview/staging and local development must use verified non-production database resources. Check the effective `DATABASE_URL` for the exact branch/environment, including branch overrides, local `.env` files and inherited shell variables, without printing credentials. Do not widen production database credentials to Preview or Development.

If a project has no Development-scoped database setting, a pulled environment file does not establish a safe database. Supply an explicitly verified development connection. A branch named `staging`, `dev` or `feat/...` is not proof of isolation.

Once the target is verified as the staging database, writing to it is agent work and needs no approval: apply `meavo-db` scripts with `scripts/apply-sql.sh staging <script>` (it refuses any other host), fix or seed staging data, and rerun scripts to prove they are idempotent. Production is read-only outside an approved release: diagnose with the workspace's guarded read-only helper (`_shared/tools/prod-read.mjs` in the local workspace), which forces a read-only transaction and never prints the connection string.

## Staging external services

A staging deployment can still talk to a real external system. Before testing a path that writes to an integration, check which account the staging credentials belong to (by its organisation or workspace name, never by printing secrets) and record it in the repository's agent notes. If the integration is shared with production (for example Sales staging uses the real Xero organisation), never create, change or delete records there from staging; cover those paths with tests, mocks or a sandbox account. Reads are fine.

## Authentication and cross-app URLs

Staging sign-in needs its applicable auth variables, such as `AUTH_SECRET`, `AUTH_GOOGLE_ID` and `AUTH_GOOGLE_SECRET`, available to that deployment. Verify their provider scopes and registered callback origins. Production-only variables can cause Auth.js configuration errors or redirect loops on previews.

Sharing an OAuth client may be an intentional project configuration when it has the staging callbacks registered. Do not infer that every auth secret must be shared or copy production values automatically. Preview and staging credential changes are agent work once their scope is verified; production credential changes need an explicit human yes. Keep database and storage credentials isolated regardless of the auth configuration.

Verify `AUTH_URL`, `GATEWAY_URL`, and other cross-app URLs for the intended environment. An arbitrary feature URL may not have an authorized callback; use the verified staging URL for sign-in testing. On an Auth.js app that exposes it, inspect `/api/auth/providers` for configured providers without printing secrets; a configuration error needs investigation, not an automatic credential change.

## Staging branch URLs

Vercel's Git integration owns each project's `<project>-git-<branch>-<team>.vercel.app` URL: it creates the alias with the first build of a branch and moves it to every later READY build of that branch, logging an `aliases-assigned` event in the same second. Never assign that URL by hand. `vercel alias set` on a staging branch URL, `vercel deploy` or `vercel redeploy` from a `staging` checkout, and API deployments carrying `staging` git metadata leave the alias on a deployment the integration did not assign itself; from then on the integration silently skips that URL on every build (the deployment still reports `aliasAssigned`, with no error and no event) and each manual re-point fixes exactly one build. This detached the sales, meavo-gateway and assembly staging URLs for weeks in 2026.

If a staging branch URL does not show the merged commit a few minutes after its build is READY, verify on that build's unique deployment URL (`<project>-<hash>-<team>.vercel.app`) and report the lag instead of re-pointing the alias. A healthy project lists the branch URL in the newest READY `staging` deployment's `alias` field and has an `aliases-assigned` event at that build's READY time.

Repairing a detached URL is staging work an agent may do without approval; the URL is unavailable for one build (about 90 seconds), so mention it in the session. Remove the alias (`vercel alias rm <branch-url> --scope <team> --yes`), trigger a Git build of `staging` without a new commit (for example a temporary deploy hook from `vercel deploy-hooks create <name> --ref staging --project <project>`, removed afterwards), and confirm that a second build moves the recreated alias automatically before relying on the URL again.

## File storage and access

Verify the actual Preview blob store and token scopes. Never widen production read/write storage credentials to Preview. A staging database copied from production can contain links to production attachments; those may be unavailable in an isolated staging store. Test new uploads only against the verified staging store.

Vercel Deployment Protection and app sign-in are separate gates. Check each project's current protection settings; do not assume staging URLs are private, globally public, or safe to share. Do not disable protection to diagnose an app login problem. Use an authorized protected-preview access method and retain the app's own authentication and tool-access checks.
