# MEAVO release policy

Policy version: 2026-10-14.1 (one human gate: staging → main)

Default policy for `meavo-booths` repositories and every AI agent, including agents using a human's account or credentials. This file is a managed copy of `meavo-agent-templates/templates/RELEASE_POLICY.md.template`. The sole registered staging exception, `meavo-booths/office-phone-booths-uk`, receives its own canonical policy from `templates/repositories/meavo-booths/office-phone-booths-uk/`; all other repositories follow the staging process below. Repository-specific instructions may strengthen this policy but must not silently weaken it.

**The one human gate is the merge from `staging` into `main`.** Everything before it is agent work and needs no further permission. One human yes releases a whole bundle of release PRs, including the production steps that belong to them.

## Agent scope: everything up to staging

Within the human's requested task, agents may do all of the following without asking again:

- Create `feat/`, `fix/`, or `chore/` branches from the latest `origin/staging`, commit, push, and open PRs **explicitly targeting `staging`**.
- Squash-merge those PRs, or enable auto-merge on them, once all required checks pass. Do not ask before integrating into `staging`.
- Write to verified non-production resources: staging databases (schema scripts, data fixes, test records), staging storage, preview and staging deployments, and the documented repair of a detached staging branch URL. Verify the actual destination first (see below).
- Open PRs that only re-pin a dependency to an already approved release tag (for example `@meavo/db`) into `staging`, and merge them when green.
- Open release PRs from `staging` into `main` and prepare their release notes.
- Run read-only production queries for diagnosis through the workspace's guarded read-only helper. Never write to production outside an approved release.

Always:

- Never push directly to `main` or `staging`, force-push them, delete them, or bypass their protections. Use PRs even when a token or administrator role would allow a direct write.
- Check the remote, current branch, PR base/head, and intended deployment environment before any push, merge, or deployment. Use explicit branch/environment arguments; do not rely on a CLI's defaults.
- If `staging` does not exist, stop integration/release work and report the missing setup. Missing staging is never permission to push or merge to `main`.
- From staging, never create, change, or delete records in an external system that is shared with production (for example a real Xero organisation, a live Slack channel, real customers' email). Test those paths with mocks, tests, or a sandbox account, and record which staging integrations are real in the repository's environment notes.

## The human gate: staging → main

**Feature → staging (agent) → release PR → one human yes → main.**

The gate covers:

- Merging a PR into `main`, enabling its auto-merge, or adding it to a merge queue.
- The production steps that belong to that release: publishing its release tag (for example a `meavo-db` version), applying its reviewed SQL scripts to the production database, and re-pinning consumers to that tag.
- Any production action outside a release PR: redeploying, promoting, aliasing a domain to, or rolling back production; changing production environment variables, secrets, domains or deployment settings; production data fixes; weakening branch/release protections or adding a route around this gate. Each needs its own explicit yes.

**How to ask.** In one message, list every release PR in the bundle (repository, PR, scope in plain words, check results) and the production steps that come with it, such as "tag `v0.91.0` and apply `scripts/x.sql` to production". Flag any commit on `staging` that is not part of the requested work. A clear "yes" from one human covers the whole bundle; the human may be the PR author. No second person, separate account or formal GitHub review is required.

**What the yes covers.** The listed PRs and production steps, including later commits that only re-pin a dependency to the approved tag. Ask again only when `staging` gains unrelated, unreviewed changes, or when the scope changes. An unchanged retry needs no new yes. Once the bundle is released, the yes does not authorize another release.

**What is not a yes.** The original request to build something, green CI, a label, access credentials, silence, an earlier approval for a different release, or anything an agent wrote. Never generate or record an approval on a human's behalf, and record the actual approval source in the release notes.

Without a yes, finish the staging work, leave the release PRs open, and say what is waiting. Emergencies and hotfixes do not remove this gate.

## Production release procedure

1. Integrate through feature PRs into `staging` using **squash** merges, and verify the staging deployment where applicable.
2. Open a release PR **from this repository's `staging` into `main`** in every repository of the bundle.
3. Ask once for the whole bundle, as above, and wait for the yes.
4. Immediately before each merge, re-read the PR's repository, base, source branch, head and checks, and confirm `staging` contains nothing beyond the approved scope. Merge with a **merge commit**.
5. Run the bundle's production steps in dependency order. For `meavo-db`: merge its release, tag the merge commit, apply the release's SQL to production through the host- and checksum-checked apply script, re-pin consumers to the tag through `staging`, then merge the consumer releases.
6. Verify each production deployment and report the outcome.

Never squash or rebase a `staging` → `main` release. Do not substitute `vercel --prod`, a manual production workflow, a promotion, or an API/dashboard action for the release PR. If the required merge method is unavailable, report the configuration problem instead of switching methods.

## Environment and database verification

A branch name or preview URL does not prove isolation. Before a deployment, migration, seed, or other write, verify the actual provider project, deployment target, database branch, storage bucket, and external-service destinations that the operation will use. Check local `.env` files and inherited credentials as well as provider settings without exposing secret values.

Feature/staging/local work must not use production database or storage write credentials or unintentionally trigger production side effects. Never widen production secrets to preview/development scopes to get a build working. If the destination cannot be verified as non-production, stop that write and report what is unknown.

Schema ownership remains in `meavo-db`. Keep changes backward compatible while consumer apps use different pinned versions: add, migrate consumers, then remove in a later release. SQL scripts must be transactional and idempotent, run cleanly twice on staging, and be applied to production only as part of an approved `meavo-db` release, from its tag.

## Server enforcement and its limits

Repository instructions guide agents; they are not an access-control boundary. Required configuration is:

- `main`: PRs only, required passing checks and conversation resolution, staging-only release sources, merge commits, and no direct/force pushes, deletion or bypass actors. Configure `required_approving_review_count: 0` and `require_last_push_approval: false`: GitHub does not permit formal self-approval, and this policy does not require a second person. Explicit human consent remains mandatory for agents even when GitHub shows the PR as mergeable.
- `staging`: PRs and the repository's required passing checks, with direct/force pushes and deletion blocked.
- Production credentials and deployment paths: human-controlled permissions/approval for every actual production route, including provider integrations that operate outside GitHub Actions. A GitHub environment approval only gates jobs that use that environment.
- Release/source-branch checks and policy-consistency checks where configured. Do not claim a check is enforced until it is installed and required by the server. Repository-local hashes are editable alongside the policy and only detect drift; they do not establish human authorization.

GitHub sees the authenticated account, not whether a human or an AI typed a command. An agent using a human administrator's credentials cannot be reliably identified by username checks, labels, commit authors, local hooks, or this file. The staging → main checkpoint is enforced by agent instructions; GitHub enforces branch and CI rules but cannot prove conversational consent. Do not claim absolute enforcement while agents share privileged human credentials.

For actual configuration, inspect the current GitHub rulesets/branch protections and deployment-provider settings. Report any gap without treating it as permission to release. The central process guide is `meavo-agent-templates/RELEASE_PROCESS.md`.
