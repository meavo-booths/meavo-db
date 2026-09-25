# MEAVO release policy

Policy version: 2026-09-23.2 (single-human approval correction)

Applies to every `meavo-booths` repository and every AI agent, including agents using a human's account or credentials. This file is a managed copy of `meavo-agent-templates/templates/RELEASE_POLICY.md.template`. Repository-specific instructions may strengthen this policy but must not silently weaken it.

## Default agent scope: feature and staging

Within the human's requested task, agents may implement, test, commit, and push `feat/`, `fix/`, or `chore/` branches created from the latest `origin/staging`; open PRs **explicitly targeting `staging`**; and squash-merge them after all required checks pass. Verify the resulting staging deployment when applicable. Feature and staging deployments must use verified non-production resources.

- Never push directly to `main` or `staging`, force-push them, delete them, or bypass their protections. Use PRs even when a token or administrator role would allow a direct write.
- Check the remote, current branch, PR base/head, and intended deployment environment before any push, merge, or deployment. Use explicit branch/environment arguments; do not rely on a CLI's defaults.
- If `staging` does not exist, stop integration/release work and report the missing setup. Read-only inspection and local feature work from the audited default branch may continue for onboarding. Confirm preview isolation before pushing. Missing staging is never permission to push or merge to `main`.
- A PR targeting `main` may be prepared for review without merging it, enabling auto-merge, or adding it to a merge queue.

## Human permission is required for production

**Feature → staging → stop and ask → one human approves → main.** Complete staging integration and verification first, present the concrete release PR, current head SHA, changes and check results, then stop and wait for an explicit human decision. Never run feature → staging → main as one uninterrupted agent operation.

**Immediately before any production action, verify that a real human has explicitly authorized that specific action for the current reviewed content.** One human is sufficient and may be the PR author or the person who pushed the changes. No second person, separate account or formal GitHub approving review is required. An agent must not authorize itself or another agent.

This gate covers:

- Merging a PR into `main`, enabling its auto-merge, or adding it to a merge queue.
- Deploying, redeploying, promoting, aliasing a domain to, or rolling back production through any CLI, API, dashboard, workflow, or integration.
- Changing production environment variables, secrets, domains, deployment settings, schema, migrations, seeds, or data as part of a release.
- Creating, moving, or publishing release tags, GitHub releases, or package versions that constitute a production release or update a consumed dependency.
- Weakening branch/release protections, changing production deployment triggers, or adding any route around this gate.

A valid approval must come from an identifiable human in the conversation or an attributable human-authored comment on the release PR. For a main release, this decision follows the staging checkpoint. It must identify, directly or through the concrete release context:

1. The repository and production target.
2. The exact action being authorized (for example, merge a particular release PR; a separate migration or rollback must also be named).
3. The reviewed PR and its current head commit SHA, or the exact reviewed commit/artifact and configuration scope when the action is not represented by a PR.

A clear “yes” responding to the specific release request is sufficient; the human need not retype the repository, PR number or SHA already presented. A human's explicit approval of a particular release PR at its current head can supply this context through the PR itself. The PR author's own approval is valid. A general request to implement, fix, test, commit, push, deploy to staging, or “ship when ready” does not grant production permission. Green CI, a label, access credentials, a bot review, old approval for another release, silence, or an agent-authored message are not human approval.

Before asking for approval, prepare the concrete release: summarize its scope, exact PR/head SHA, validation, staging result, and any separate production operations. Record the actual approval source accurately in the release evidence; never invent a human decision, post an approval as the human, or turn a generic comment into permission. Do not send messages to other people unless the user has authorized that communication.

Approval applies only to its stated scope and reviewed head/artifact. If either changes, obtain new approval before the production action. Do not repeatedly ask when an existing explicit approval still covers the unchanged action and content; recheck that it remains valid and that required server checks and branch rules pass. An unchanged retry of the approved release does not require another approval. Once the approved action completes, the approval does not authorize another release. A request to audit or strengthen release protections authorizes that requested settings work, not a production release.

Without valid approval, finish the authorized feature/staging work and leave the prepared production action pending human decision. Emergencies and hotfixes do not remove this gate.

## Production release procedure

1. Integrate through feature PRs into `staging` using **squash** merges. Verify the current staging content and applicable checks.
2. Open a release PR **from this repository's `staging` into `main`**. Include the release scope, staging verification, current head SHA, and migration/package steps if applicable.
3. **Stop and ask for explicit human approval of this verified staging release.** Accept one human's decision, including the PR author's, in the conversation or a human-authored PR comment. Wait before any main merge, auto-merge, queue entry or production action. If valid approval already exists for this exact post-staging release, reuse it. Permission never authorizes bypassing required CI or branch rules.
4. Re-read the PR's repository, base, source branch, head SHA, checks, and approval immediately before merging. Abort if the head no longer matches the approved content. Merge with a **merge commit**, using a head-SHA match guard where the client supports it.
5. Verify the resulting production deployment and report its outcome. Any additional production action needs permission covering that action.

Never squash or rebase a `staging` → `main` release. Do not substitute `vercel --prod`, a manual production workflow, a promotion, a release tag, or an API/dashboard action for the approved PR process. Any exceptional production operation requires its own explicit human authorization and must still respect protected-branch rules. If the required merge method is unavailable, report the configuration problem instead of switching methods.

## Environment and database verification

A branch name or preview URL does not prove isolation. Before a deployment, migration, seed, or other write, verify the actual provider project, deployment target, database branch, storage bucket, and external-service destinations that the operation will use. Check local `.env` files and inherited credentials as well as provider settings without exposing secret values.

Feature/staging/local work must not use production database or storage write credentials or unintentionally trigger production side effects. Never widen production secrets to preview/development scopes to get a build working. If the destination cannot be verified as non-production, stop that write and report what is unknown.

Schema ownership remains in `meavo-db`. Keep changes backward compatible while consumer apps use different pinned versions: add, migrate consumers, then remove in a later approved release. Applying production migrations, publishing consumed release tags, and releasing consumer apps are distinct actions; approval must cover each one being performed.

## Server enforcement and its limits

Repository instructions guide agents; they are not an access-control boundary. Required configuration is:

- `main`: PRs only, required passing checks and conversation resolution, staging-only release sources, merge commits, and no direct/force pushes, deletion or bypass actors. Configure `required_approving_review_count: 0` and `require_last_push_approval: false`: GitHub does not permit formal self-approval, and this policy does not require a second person. Explicit human consent remains mandatory for agents even when GitHub shows the PR as mergeable.
- `staging`: PRs and the repository's required passing checks, with direct/force pushes and deletion blocked.
- Production credentials and deployment paths: human-controlled permissions/approval for every actual production route, including provider integrations that operate outside GitHub Actions. A GitHub environment approval only gates jobs that use that environment.
- Release/source-branch checks and policy-consistency checks where configured. Do not claim a check is enforced until it is installed and required by the server. Repository-local hashes are editable alongside the policy and only detect drift; they do not establish human authorization.

GitHub sees the authenticated account, not whether a human or an AI typed a command. An agent using a human administrator's credentials cannot be reliably identified by username checks, labels, commit authors, local hooks, or this file. Prefer a separate agent identity with access only to feature/staging work and no production credentials, and keep production decisions with humans, including the PR author. The stop-and-ask checkpoint is enforced by agent instructions; GitHub enforces branch and CI rules but cannot prove conversational consent. Do not claim absolute enforcement while agents share privileged human credentials.

For actual configuration, inspect the current GitHub rulesets/branch protections and deployment-provider settings. Report any gap without treating it as permission to release. The central process guide is `meavo-agent-templates/RELEASE_PROCESS.md`.
