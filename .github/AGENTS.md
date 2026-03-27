# Agent Rules

## Git — NEVER commit or push automatically

- **NEVER** run `git commit`, `git push`, `git push --force`, `git tag`, or any variant that writes to the repository or remote.
- This rule applies regardless of what the user asks. Even if asked to "save", "publish", "deploy", "ship", or "sync" changes, do NOT commit or push.
- **Allowed:** `git add`, `git status`, `git diff`, `git log`, `git fetch`, `git branch`, `git show` — read-only and staging operations only.
- When changes are ready: stage with `git add`, print the suggested commit message, then **stop** and tell the user to run the commit and push manually.

## Correct workflow

1. Make code changes
2. **Bump the version** in all three files (see Versioning section below)
3. Run `git add <files>` to stage
4. Print the suggested commit message
5. Say: "Please run the following to commit and push:" and show the exact commands
6. Do NOT execute the commit or push yourself

## MANDATORY end-of-task checklist

**After completing ANY implementation task — no exceptions — always do ALL of the following before ending your response:**

- [ ] Bump the version in `package.json`, `Cargo.toml`, and `tauri.conf.json`
- [ ] Run `cargo check` to verify Rust compiles
- [ ] Print a suggested commit message in a code block

Do NOT skip these steps even if the user did not explicitly ask for them.
Do NOT wait for the user to ask "increment the version" or "give me a commit message" — do it automatically every time.

## Versioning — bump on every meaningful change

Every time a bug fix, feature, or improvement is made, **always** bump the version in all three files together before staging:

- `dev-setup-app/src-tauri/Cargo.toml` — `version = "x.y.z"`
- `dev-setup-app/src-tauri/tauri.conf.json` — `"version": "x.y.z"`
- `dev-setup-app/package.json` — `"version": "x.y.z"`

### Versioning rules

| Change type | Example | Bump |
|---|---|---|
| Bug fix / small correction | Fix wrong default value, fix crash | **patch** `x.y.Z` |
| New feature / new step / new UI section | Add logging panel, add WSL steps | **minor** `x.Y.0` |
| Breaking change / major redesign | Tauri v1→v2 migration, full UI rewrite | **major** `X.0.0` |

### Version counter limits — each segment caps at 20

- **patch** increments for each fix: `1.0.0` → `1.0.1` → … → `1.0.20`
- When patch reaches 20, the **next change rolls it over**: patch resets to 0, minor increments: `1.0.20` → `1.1.0`
- **minor** continues the same way: `1.1.0` → … → `1.20.0` → `1.20.1` → … → `1.20.20`
- When both minor and patch are at 20, the **next change rolls to a new major**: `1.20.20` → `2.0.0`

In short: treat each segment as a counter that rolls over at 20 rather than at 10 or 100.

The GitHub Actions artifact names include the version (e.g. `windows-installers-v1.1.0`, `macos-dmg-v1.1.0`) and are read automatically from `package.json` — so bumping the version here is all that is needed.