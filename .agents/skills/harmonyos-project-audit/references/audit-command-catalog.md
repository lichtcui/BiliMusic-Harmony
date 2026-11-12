# Read-only audit command catalog

Run commands from the intended project root. Quote paths containing spaces. Replace placeholders; do not paste secrets into shell history.

## Git boundary

```powershell
git rev-parse --show-toplevel
git branch --show-current
git rev-parse HEAD
git status --short --branch
git diff --cached --name-only
git clean -ndX
git worktree list --porcelain
```

`git clean -ndX` is preview-only. Never remove `-n` during Gate A.

Find applicable instructions from root to target, then read only the relevant documents:

```powershell
rg --files -g AGENTS.md -g README.md -g 'docs/**'
```

## HarmonyOS project inventory

List candidate configuration without dumping credential values:

```powershell
rg --files -g build-profile.json5 -g hvigor-config.json5 -g hvigorfile.ts -g oh-package.json5 -g module.json5
rg -n 'compileSdkVersion|compatibleSdkVersion|targetSdkVersion|runtimeOS|buildModeSet|products|modules|targets' --glob '*.json5'
```

For signing, report only counts, binding names if they are safe to disclose, and whether required fields exist. Do not print the values of `storePassword`, `keyPassword`, private paths, or certificate identity fields.

## Build and test evidence

- Locate wrappers and task configuration before choosing a command.
- Record the exact command, exit code, first causal error, and final task state.
- Distinguish test task completion from a verified test-case count.
- Distinguish assemble success, package signing, installation, launch, and human runtime verification.

Do not run a build merely to make the audit look complete if it writes outputs outside the allowed scope or requires signing credentials.
