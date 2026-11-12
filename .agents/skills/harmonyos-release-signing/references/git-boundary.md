# Git boundary for local signing

## Three independent checks

1. **Tracked now** — inspect the current tree for signing material or local-only signing configuration.
2. **Staged now** — inspect the index separately; an ignored file can still have been force-added.
3. **Reachable history** — inspect commits reachable from current refs for prohibited signing material names and runtime-only private markers without printing their contents.

Real signing material in reachable history is `SIGNING_SECRET_INCIDENT`. Stop further publication and pushing. Provide an incident recovery plan, but never rewrite history, force push, rotate credentials, or delete remote refs without explicit human authorization.

## Preflight

```powershell
git status --short
git ls-files
git diff --cached --name-only
git log --all --name-only --pretty=format:
```

Inspect outputs for credential file extensions and local signing config. Do not print the content of a sensitive diff.

## Repository-external private patch

When a tracked configuration must be changed locally for signing:

1. Confirm the tracked file is clean and record its blob hash.
2. Create the signing diff in a private location outside the repository.
3. Hash the private patch and store the hash separately from public project content.
4. Apply it locally without staging.
5. Build and verify the final artifact.
6. Restore the tracked file from the known repository blob using a non-destructive, explicit file operation.
7. Confirm the restored file hash, `git diff --check`, and `git status --short`.
8. Remove the private patch according to the user's credential-retention policy.

Never print the patch or its sensitive lines. Never use a broad reset or cleanup command to restore it.

## History incident

If real signing material entered Git history, stop push/publication. Record affected refs and obtain authorization for a dedicated history-rewrite and credential-rotation plan. Deleting the working file is not remediation.
