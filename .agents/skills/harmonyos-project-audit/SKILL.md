---
name: harmonyos-project-audit
description: Establish a read-only, evidence-based baseline for a HarmonyOS or DevEco Studio project before edits. Use when first taking over a project, recovering its state, scoping a requested change, checking Git and build configuration, or deciding whether a failure belongs to the environment, configuration, or application.
---

# HarmonyOS Project Audit

## Scope

Audit first. Do not modify the target project during Gate A. Separate confirmed facts, risks, and unknowns; then propose one minimal next action.

## Use when

Use for first inspection, takeover, recovery, scope discovery, or a read-only baseline before any edit.

## Do not use when

Do not use as the primary skill for deep CLI environment repair, signing configuration, final artifact verification, or publication orchestration.

## Handoff

After the baseline, recommend exactly one primary next skill when needed: Build Doctor for an environment failure, Release Signing for signing readiness, or Release Check for a final candidate. A recommendation does not invoke another skill automatically.

## Required inputs

- Target project path and the user's requested outcome.
- Applicable repository instructions such as `AGENTS.md`.
- Permission boundary: read-only audit or an explicitly authorized modification.
- Any known build command, failure text, test command, or DevEco Studio version.

## Workflow

### Gate A: read-only audit

1. Resolve the target path and Git root. Stop if the resolved Git root is broader than intended.
2. Record branch, HEAD, tracked/staged/dirty state, ignored generated outputs, and worktrees without changing them.
3. Read applicable `AGENTS.md`, the primary README, and only the docs needed to establish current status and requested scope.
4. Inventory project-level and module-level build profiles, Hvigor configuration, package manifests, modules, products, build modes, target SDK/API declarations, and build entrypoints.
5. Report bundle identities redacted unless the user needs the exact value and disclosure is authorized.
6. Count signing configurations and product bindings without printing aliases, credential fields, certificate identities, or full sensitive diffs.
7. Identify the current build mode, known tests, latest verified evidence, and unverified claims. A successful compile is not runtime proof.
8. Classify high-risk actions: signing, publishing, persistent environment changes, data/schema migrations, permission expansion, destructive Git operations, and generated-artifact cleanup.
9. Produce the Gate A output contract below. Do not edit files.

Use [the audit command catalog](references/audit-command-catalog.md) for bounded commands and [risk classification](references/risk-classification.md) for stop decisions.

### Gate B: modification

Enter only when the user explicitly authorizes a change.

1. Restate the smallest allowed file and behavior scope.
2. Capture pre-change evidence relevant to that scope.
3. Make only the authorized change; do not opportunistically refactor or optimize.
4. Run focused validation, then the narrowest meaningful build or test.
5. Capture post-change evidence with `git diff --check` and `git status --short`.
6. Report changed files, actual test/build outcomes, remaining unknowns, and the next verification boundary.

## Decision rules

- Treat filesystem and command output as stronger evidence than stale documentation.
- Treat a DevEco/Node/SDK/Java startup failure as an environment hypothesis before changing application code.
- Preserve human decisions and declared deferred checks.
- Report `not run`, `blocked`, and `unknown` exactly; never convert them into success.
- Prefer the project's established build entrypoint and product/module parameters.

## Stop conditions

Stop before changes if the Git root is ambiguous, the requested scope conflicts with repository instructions, evidence may expose credentials/private data, or modification authority is absent. Stop before destructive, signing, publishing, permission, schema, or data operations unless specifically authorized.

## Forbidden actions

- Do not edit during Gate A.
- Do not reset, clean, discard, stage, commit, or push the target repository during an audit.
- Do not treat old code or optional improvements as authorization to refactor.
- Do not print password values, private keys, full signing configuration, or unrelated personal paths.
- Do not claim device or simulator verification from build output alone.

## Output contract

Return exactly these sections:

1. **Current state** — root, branch/HEAD, change state, project/build inventory, and verified evidence.
2. **Risks** — ranked, evidence-linked risks within the requested scope.
3. **Unknowns** — facts not established and why.
4. **Proposed minimal next action** — one bounded action, required authorization, and validation.

For Gate B, also return changed files, before/after evidence, `git diff --check`, `git status --short`, and build/test results.

Optionally append redacted machine-readable evidence conforming to the repository's [evidence schema](https://github.com/zhangifexim-bit/harmonyos-agent-skills/blob/main/schemas/evidence.schema.json). Keep human-readable sections authoritative; never place secrets or personal absolute paths in evidence JSON.

## Validation

Confirm every factual statement maps to a file, command, or user-supplied result. Confirm no audit command mutated the project and no sensitive value appears in the output.
