---
name: harmonyos-release-signing
description: Audit, configure, and validate HarmonyOS Release signing without exposing credentials. Use when working with build-profile signingConfigs, Debug versus Release identities, keyAlias, certpath, profile, storeFile, storePassword, keyPassword, product signing bindings, SignHap/SignApp tasks, or Git-safe local signing configuration.
---

# HarmonyOS Release Signing

## Scope

Handle signing as a credential boundary. Keep real signing material outside the repository and keep Release identity separate from Debug identity.

## Use when

Use to audit or configure `signingConfigs`, Debug/Release identity separation, credential fields, product bindings, local signing configuration, and Git boundaries.

## Do not use when

Do not use as the final publication orchestrator. It does not select the final APP, perform the human smoke-test gate, create tags, publish, or call Release Check.

## Handoff

This is a leaf skill. It outputs `SIGNING_READY` only when its own gates pass and may say `Recommended next skill: harmonyos-release-check`. That recommendation is not an invocation and cannot recurse.

## Required inputs

- Project root, target product, release build mode, and expected public bundle identity.
- Sanitized signing configuration shape and the locations of credential files, described without secret values.
- Expected certificate identity/profile type from an authorized source.
- Current Git tracked, staged, and history state.

## Workflow

1. Audit `signingConfigs` and `products.<product>.signingConfig` bindings without printing sensitive values.
2. Confirm Release and Debug do not share an unintended identity or profile.
3. Check presence and repository boundary for `keyAlias`, `certpath`, `profile`, `storeFile`, `storePassword`, and `keyPassword`.
4. Classify password fields using [the signing configuration model](references/build-profile-signing.md). A non-empty field is not proof of plaintext.
5. Check separately whether `.p12`, `.p7b`, `.cer`, keystores, local profiles, or signing patches are tracked now, staged now, or present in reachable history. If real signing material is reachable, report `SIGNING_SECRET_INCIDENT`, stop, and provide a recovery plan without rewriting history.
6. If modification is authorized, change only the selected Release config and product binding. Do not alter Debug signing unless required and approved.
7. Validate signing readiness from configuration, binding, identity/profile expectations, credential boundaries, and repository state. Do not run formal `assembleApp`, SignHap, or SignApp tasks; Release Check owns the single formal Release build.
8. Restore any tracked local-only signing difference and confirm Git clean.
9. Return `SIGNING_READY` or an exact blocked/failed state. Do not perform build or final artifact orchestration.

For a repository-external private patch workflow, read [the Git boundary guide](references/git-boundary.md).

## Decision rules

Classify each password field without revealing it:

- `EMPTY`: absent or empty.
- `DEVECO_CIPHERTEXT_CONFIRMED`: verified by the active DevEco tooling or documented local format, without printing the value.
- `DEVECO_CIPHERTEXT_LIKELY`: matches a known local ciphertext structure but was not independently verified.
- `PLAINTEXT_LIKELY`: evidence strongly indicates an unprotected literal and it is not a placeholder.
- `UNDETERMINED`: insufficient evidence; fail closed and request a safe local verification.

Never infer `PLAINTEXT_LIKELY` solely from non-emptiness.

## Stop conditions

Stop before declaring readiness or committing if signing material is inside the repository, credential classification is unsafe, Release identity/profile expectations are unavailable, the product binding is ambiguous, or a real secret may be in Git history. Stop before formal build, key generation, certificate replacement, account actions, upload, or publication; those actions are outside this skill.

## Forbidden actions

- Do not output passwords, private keys, ciphertext values, full sensitive diffs, private patches, or real fingerprints.
- Do not add `.p12` or `.p7b`; keep `.cer` outside Git by default.
- Do not use a Debug profile or identity merely because it produces a signed artifact.
- Do not commit a local `build-profile.json5` signing difference.
- Do not rewrite history without an explicit incident-recovery plan and authorization.

## Output contract

Return a redacted table of configuration fields, presence, classification, repository boundary, and evidence. Then report product binding, `SIGNING_READY` status, Git tracked/staged/reachable-history checks, cleanup status, unresolved human confirmations, and the optional recommendation to use Release Check next. Do not require or report formal build, final APP verification, or smoke-test completion as a condition of this output.

Optionally append redacted JSON conforming to the repository's [evidence schema](https://github.com/zhangifexim-bit/harmonyos-agent-skills/blob/main/schemas/evidence.schema.json). Never include credential values, fingerprints, private patches, or personal absolute paths.

## Validation

Require unambiguous Release signing configuration and product binding, expected certificate/profile/bundle inputs from an authorized source, safe credential classification, no signing material in Git, restored tracked configuration, and clean Git state. Do not require formal `assembleApp`, final APP independent verification, smoke testing, or reverse validation by Release Check. Those downstream gates belong only to Release Check.
