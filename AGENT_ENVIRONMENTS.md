# Development and staging environments

Read `RELEASE_POLICY.md` before release, deployment, environment, schema or package operations. These instructions describe what to verify; they do not assert that a particular provider setting is currently enabled.

## Before a push or build

Inspect Git deployment triggers, install/build scripts, and the actual target environment. A documentation-only push can still start a build; some MEAVO builds run SQL, backfills or external-service code. Do not start those writes until their non-production destinations are verified. Do not change deployment triggers or credentials silently to make a build pass.

## Database and local development

Preview/staging and local development must use verified non-production database resources. Check the effective `DATABASE_URL` for the exact branch/environment, including branch overrides, local `.env` files and inherited shell variables, without printing credentials. Do not widen production database credentials to Preview or Development.

If a project has no Development-scoped database setting, a pulled environment file does not establish a safe database. Supply an explicitly verified development connection. A branch named `staging`, `dev` or `feat/...` is not proof of isolation.

## Authentication and cross-app URLs

Staging sign-in needs its applicable auth variables, such as `AUTH_SECRET`, `AUTH_GOOGLE_ID` and `AUTH_GOOGLE_SECRET`, available to that deployment. Verify their provider scopes and registered callback origins. Production-only variables can cause Auth.js configuration errors or redirect loops on previews.

Sharing an OAuth client may be an intentional project configuration when it has the staging callbacks registered. Do not infer that every auth secret must be shared or copy production values automatically. Credential changes require the existing environment/release approval scope. Keep database and storage credentials isolated regardless of the auth configuration.

Verify `AUTH_URL`, `GATEWAY_URL`, and other cross-app URLs for the intended environment. An arbitrary feature URL may not have an authorized callback; use the verified staging URL for sign-in testing. On an Auth.js app that exposes it, inspect `/api/auth/providers` for configured providers without printing secrets; a configuration error needs investigation, not an automatic credential change.

## File storage and access

Verify the actual Preview blob store and token scopes. Never widen production read/write storage credentials to Preview. A staging database copied from production can contain links to production attachments; those may be unavailable in an isolated staging store. Test new uploads only against the verified staging store.

Vercel Deployment Protection and app sign-in are separate gates. Check each project's current protection settings; do not assume staging URLs are private, globally public, or safe to share. Do not disable protection to diagnose an app login problem. Use an authorized protected-preview access method and retain the app's own authentication and tool-access checks.
