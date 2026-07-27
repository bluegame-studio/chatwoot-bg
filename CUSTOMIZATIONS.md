# BG Chatwoot Maintenance

This fork preserves the official Chatwoot Git history. The `bg/v4.16.1`
maintenance branch starts from upstream tag `v4.16.1` at
`0882dc929153203137478a906a5eefdced01a63f` and contains only the BG-specific
commits required for delivery and avatar caching.

## Current Customizations

- `f56262590` ports the Active Storage avatar representation proxy behavior
  from `714dfa7035c1c75ff64151b96de582e8a69404c9`. This lets Cloudflare cache
  image bytes instead of following a private object-storage redirect.
- `3ec11036b` ports the Jenkins `SOURCE_COMMIT` build metadata behavior from
  `b3decf637acfa4efe654ba8bcac1de849b2722ad`.
- `SOURCE_COMMIT` is intentionally declared after dependency installation and
  asset compilation in `docker/Dockerfile`. Moving it near the top invalidates
  expensive dependency layers on every application commit.

Use `git log upstream/v4.16.1..bg/v4.16.1 --reverse` to audit every fork
commit. Pipeline definitions are intentionally owned by the private
`bg-devops` repository rather than this application repository.

## Development Workflow

1. Update the local maintenance branch with `git pull --ff-only origin
   bg/v4.16.1`.
2. Create a short-lived `feat/*`, `fix/*`, or `perf/*` branch from
   `bg/v4.16.1`.
3. Follow `AGENTS.md`, including checks for matching Enterprise overlay code.
4. Keep custom behavior in focused Conventional Commits and run the tests that
   cover each changed area.
5. Merge reviewed work into `bg/v4.16.1`. Never force-push a maintenance branch
   after an image built from it has been deployed.

## Upstream Upgrade

Fetch official tags through the read-only `upstream` remote, create a new
maintenance branch from the target tag, and reapply only the BG behavior that
is still required:

```text
git fetch upstream --tags
git switch -c bg/v<new-version> upstream/v<new-version>
```

Resolve changes against the new upstream implementation, record the originating
BG commit in each ported commit message, update this file, and verify database
migrations plus the dev deployment before production. Keep previous maintenance
branches and immutable image tags for rollback.
