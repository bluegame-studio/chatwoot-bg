# BG Chatwoot Maintenance

This fork preserves the official Chatwoot Git history. The `bg/v4.11.1`
maintenance branch starts from upstream tag `v4.11.1` at
`a08125e283b8e15b84b5073def1e785137b059ba` and contains the BG-specific commits
on top.

## Current Customization

- `714dfa7035c1c75ff64151b96de582e8a69404c9` proxies Active Storage avatar
  representations through the application URL so Cloudflare can cache them.

Use `git log upstream/v4.11.1..bg/v4.11.1 --reverse` to audit every fork commit.
Pipeline definitions are intentionally owned by the private `bg-devops`
repository rather than this application repository.

## Development Workflow

1. Update the local maintenance branch with `git pull --ff-only origin
   bg/v4.11.1`.
2. Create a short-lived `feat/*`, `fix/*`, or `perf/*` branch from
   `bg/v4.11.1`.
3. Follow `AGENTS.md`, including checks for matching Enterprise overlay code.
4. Keep custom behavior in focused Conventional Commits and run the tests that
   cover each changed area.
5. Merge reviewed work into `bg/v4.11.1`. Never force-push a maintenance branch
   after an image built from it has been deployed.

## Upstream Upgrade

Fetch official tags through the read-only `upstream` remote, create a new
maintenance branch from the target tag, and cherry-pick only the BG behavior
commits that are still required:

```text
git fetch upstream --tags
git switch -c bg/v<new-version> upstream/v<new-version>
git cherry-pick <required-bg-commit> [...]
```

Resolve conflicts against the new upstream implementation, update the current
customization list, and verify the dev deployment before production. Keep the
previous version branch and immutable image tags for rollback.
