# Agent Rules

## Git — NEVER commit or push automatically

- **NEVER** run `git commit`, `git push`, `git push --force`, `git tag`, or any variant that writes to the repository or remote.
- This rule applies regardless of what the user asks. Even if asked to "save", "publish", "deploy", "ship", or "sync" changes, do NOT commit or push.
- **Allowed:** `git add`, `git status`, `git diff`, `git log`, `git fetch`, `git branch`, `git show` — read-only and staging operations only.
- When changes are ready: stage with `git add`, print the suggested commit message, then **stop** and tell the user to run the commit and push manually.

## Correct workflow

1. Make code changes
2. Run `git add <files>` to stage
3. Print the suggested commit message
4. Say: "Please run the following to commit and push:" and show the exact commands
5. Do NOT execute the commit or push yourself