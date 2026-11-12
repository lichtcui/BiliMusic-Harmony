---
name: harmonyos-release-check
description: Run the final evidence-based gate for a HarmonyOS publication candidate. Use when building a Release APP, reviewing SignHap/SignApp results, verifying a final .app with hap-sign-tool, checking certificate/profile/bundle identity and digest, coordinating a human device smoke test, restoring local signing config, or deciding whether commit/tag/release is allowed.
---

# HarmonyOS Release Check

## Scope

Verify the exact final artifact independently. A successful assemble task or the existence of a signed file is not sufficient release evidence.

## Use when

Use for a final Release candidate: signing-evidence orchestration, fresh APP selection, independent verification, SHA-256 identity, human smoke testing, cleanup, and the publication readiness decision.

## Do not use when

Do not use for an initial project baseline, an isolated environment startup failure, signing configuration alone, or any publication action that lacks separate authorization.

## Handoff

Release Check is the only release orchestrator. It may call `$harmonyos-release-signing` at most once in one invocation when valid signing-audit evidence is absent. Reuse valid signing evidence, and must not recurse into itself or ask Release Signing to invoke it.

## Required inputs

- Clean intended Git commit and explicit release scope.
- Product, module set, Release build mode, expected bundle, certificate identity, and profile type.
- Project-supported Release assemble command.
- Final `.app` path and access to the official `hap-sign-tool.jar` plus JBR/Java.
- Human owner for device smoke testing and publication approval.

## Workflow

1. Before entering `SIGNING_READY`, run a distinct Git preflight: confirm the correct repository root, intended HEAD, tracked and staged scope, ignored outputs, and credential boundary. Stop on any mismatch.
2. Reuse valid `SIGNING_READY` evidence when available. Otherwise audit Release configuration and product/signing binding with `$harmonyos-release-signing` once. Do not build until `SIGNING_READY` is established.
3. As the only formal Release build orchestrator, run the project-supported Release `assembleApp` command exactly once. Capture exact command, exit code, and completed build/sign tasks; do not ask Release Signing to build first.
4. Confirm SignHap and SignApp evidence when the local Hvigor version exposes those task names.
5. Record the build start/end timestamps, discover pre-existing and post-build outputs, and resolve exactly one newly produced final `.app`; reject stale or ambiguous candidates.
6. Read [the hap-sign-tool verification guide](references/hap-sign-tool-verification.md), inspect local help, and run `verify-app` into a new temporary directory.
7. Hash the final artifact with SHA-256 and record that digest as the immutable artifact identity.
8. Verify the extracted certificate chain against the expected Release identity without publishing the real fingerprint.
9. Verify the extracted profile, profile type, validity, and expected bundle using the active tool's supported read-only commands.
10. Prove the candidate is Release, not Debug, from build mode plus profile/identity evidence.
11. Select the device-test path after `ARTIFACT_VERIFIED`: directly install the exact artifact only when its signing/distribution policy permits that channel. Otherwise, the only permitted distribution before `SMOKE_TESTED` is staging the same unchanged verified candidate in a supported pre-release AppGallery test channel, solely for device testing and only after explicit user authorization. This staging is not formal submission or production publication. Without that separate authorization, request it and do not stage. Read [the AppGallery test-channel validation guide](references/appgallery-test-channel-validation.md).
12. Require a human device smoke test traceable to the exact release-candidate identity: commit, versionName, versionCode, platform buildVersion when present, and final APP SHA-256. A matching filename is insufficient.
13. Treat human smoke testing as experience-level evidence (visible blocking, initial response, and navigation/state correctness). Obtain millisecond measurements only from instrumentation.
14. Restore local-only signing configuration and confirm Git clean.
15. After `GIT_CLEAN`, require `PUBLIC_IDENTITY_POLICY_PASS` for a public repository that declares a publication identity policy. This named condition checks the candidate and any supplied annotated release tag without adding another publication state.
16. Allow commit or tag only after all required evidence passes and the user separately authorizes it.

Use [the release gate matrix](references/release-gate.md) to classify each stage.

## Publication state machine

Advance only in order:

```text
SIGNING_READY -> BUILD_READY -> ARTIFACT_VERIFIED -> SMOKE_TESTED -> GIT_CLEAN -> READY_FOR_PUBLICATION
```

Every transition requires its own evidence. Missing, failed, stale, or mismatched evidence blocks the next state.

`PUBLIC_IDENTITY_POLICY_PASS` is a required named condition after `GIT_CLEAN` and before `READY_FOR_PUBLICATION` when the public repository declares a policy. It is not a seventh state and does not restrict ordinary non-merge contributor identities.

The preflight Git gate occurs before `SIGNING_READY`; it does not replace the later `GIT_CLEAN` transition after the build, verification, and smoke test.

## Decision rules

- Fail closed on multiple artifacts, unknown tool versions, verification nonzero exit, identity mismatch, Debug profile, bundle mismatch, stale output, or unclean Git.
- Treat `verify-app` and `verify-profile` command syntax as version-sensitive; inspect local help before execution.
- Write extracted certificate/profile evidence only to a fresh temporary directory and avoid console output containing private identity details.
- Keep build, signing, verification, device testing, and publication as separate states.
- Diagnose device-install failures channel-first: establish the candidate's signing/distribution type and requested install channel before investigating a package defect. A device-side signature error alone is not final proof that the APP is damaged.
- Keep AppGallery upload acceptance, package legality/parsing, pre-release or listing self-check, invitation/open testing, and formal submission/publication as separate evidence states. A pre-release AppGallery test channel never satisfies publication authorization.

## Stop conditions

Stop before device installation or test distribution if independent verification fails. Before `SMOKE_TESTED`, do not upload except for the explicitly user-authorized staging of the unchanged `ARTIFACT_VERIFIED` candidate in a supported pre-release AppGallery test channel solely for device testing. Stop before formal submission, production publication, tag, Release, or production/listing visibility change outside that explicitly authorized pre-release test-channel path if any publication gate is incomplete, Git is dirty, the human smoke test is missing, a required publication identity policy has not passed, or separate publication authorization is absent.

## Forbidden actions

- Do not hardcode a DevEco Studio, JBR, SDK, keystore, or user path.
- Do not print real certificate fingerprints, private profiles, passwords, or signing diffs.
- Do not verify an intermediate HAP and infer that the final APP matches.
- Do not substitute Debug signing for Release.
- Do not uninstall an installed formal application without explicit user authorization.
- Do not re-sign, rebuild, or otherwise change the candidate SHA merely to diagnose an install failure that may be explained by channel policy.
- Do not create a tag or release as a side effect of verification.

## Output contract

Return a gate table with `PASS`, `FAIL`, `BLOCKED`, or `NOT_RUN` for Git scope, Release config, assembleApp, SignHap, SignApp, final APP selection, `verify-app`, digest, certificate identity, profile, bundle, Release-vs-Debug, device-test channel, human smoke test, local config restore, and Git clean. Keep AppGallery statuses separate and include safe evidence and one next action for each non-pass state.

Also report the highest publication state reached. Optionally append redacted JSON conforming to the repository's [evidence schema](https://github.com/zhangifexim-bit/harmonyos-agent-skills/blob/main/schemas/evidence.schema.json); artifact evidence may include SHA-256 but never a secret, fingerprint, private profile, or personal absolute path.

## Validation

Re-hash the artifact after all checks and compare it with the smoke-tested file. Confirm temporary verification outputs are outside Git, local signing changes are restored, and no tag/release/publication action occurred without explicit authorization.
