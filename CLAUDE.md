<!-- BEGIN MEAVO RELEASE POLICY -->
## MEAVO release safety

Read [AGENTS.md](AGENTS.md) and [RELEASE_POLICY.md](RELEASE_POLICY.md) before release or deployment work. The only human gate is merging `staging` → `main`. Everything before it is agent work and needs no further permission: feature branches, PRs into `staging`, squash-merging or enabling auto-merge on them when checks pass, writes to verified staging resources, re-pins to approved tags, release PRs, and read-only production queries through the guarded helper. To release, list every release PR in the bundle with its scope and production steps (release tag, production SQL) in one message; one human yes covers the bundle, including re-pins to the approved tag. Ask again only if `staging` gains unrelated changes. Never push directly to `main`/`staging`, bypass protections, or change production outside an approved release.
<!-- END MEAVO RELEASE POLICY -->

@AGENTS.md
