# Release gate matrix

## Required state order

```text
SIGNING_READY -> BUILD_READY -> ARTIFACT_VERIFIED -> SMOKE_TESTED -> GIT_CLEAN -> READY_FOR_PUBLICATION
```

No state may be inferred from a later state. Each transition needs independent evidence.

Before the state machine starts, run a separate Git preflight that proves the correct root, intended HEAD, tracked/staged scope, and credential boundary. This pre-build audit does not satisfy the later `GIT_CLEAN` state.

For a public repository that declares a publication identity policy, require the named condition `PUBLIC_IDENTITY_POLICY_PASS` after `GIT_CLEAN` and before `READY_FOR_PUBLICATION`. It validates publication-control identities without adding a seventh state or rejecting ordinary non-merge contributors solely for using a valid public email.

| Gate | PASS evidence | Fail closed when |
| --- | --- | --- |
| Git scope | Intended HEAD, reviewed diff, no credentials | Wrong root, unrelated changes, sensitive files |
| Release config | Expected product, Release build mode, Release signing binding | Missing/ambiguous binding or Debug identity |
| Signing | Expected SignHap/SignApp evidence or documented equivalent | Skipped/failed/ambiguous signing |
| Build | Release assembleApp exits zero after signing readiness | Failed task, duplicate formal build, or unknown artifact provenance |
| Final artifact | Exactly one fresh `.app` tied to the build | Stale or multiple candidates |
| Signature | Official `verify-app` exits zero | Nonzero, unsupported syntax, missing outputs |
| Identity/profile | Expected certificate, Release profile, expected bundle | Mismatch, expired/invalid, Debug, unknown |
| Digest | SHA-256 recorded and stable | Artifact changes after verification |
| Device-test channel | Candidate signing/distribution policy permits direct install, or the user explicitly authorizes the unchanged verified candidate for a supported pre-release AppGallery test channel | Channel is unknown, incompatible, or test-channel staging lacks explicit authorization |
| Device smoke | Human tests the exact candidate identity on the selected device-test channel | Candidate identity differs, not run, or failed observation |
| Cleanup | Local signing diff restored; temp evidence outside Git | Dirty tracked config or staged material |
| Public identity policy | Candidate control identities and any supplied annotated-tag tagger match the repository policy | Policy missing/invalid, history incomplete, ref unresolved, or publication-control identity unauthorized |
| Publication | Separate explicit authorization | Any gate incomplete or no authorization |

`BLOCKED` is not `FAIL`: use it when required external evidence or human testing is unavailable. Neither state permits publication.

Freshness requires build start/end timestamps, pre/post output discovery, and SHA-256. The SHA-256 digest is the immutable artifact identity. The exact release-candidate identity jointly identifies commit, versionName, versionCode, platform buildVersion when present, and final APP SHA-256. The device smoke-test record must be traceable to that same identity; filename equality is not identity evidence.

For a release-signed candidate, direct installation is allowed only when the selected local/development channel accepts its signing and distribution policy. If it does not, after `ARTIFACT_VERIFIED` the unchanged candidate may proceed through an explicitly authorized supported pre-release AppGallery test channel, after the platform's required acceptance checks, and then to human smoke testing. Invitation testing can be restricted to a test group; public/open testing can reach broader or public testers. Both are pre-production test distribution, not formal production publication, and neither satisfies the separate Publication gate. Available channels and visibility must be verified against the current AppGallery Console or official rules.

Report AppGallery upload acceptance, package legality/parsing acceptance, pre-release or listing self-check, invitation/open testing, and formal submission/publication independently. Do not infer a later state from an earlier one. See [AppGallery test-channel validation](appgallery-test-channel-validation.md) for channel diagnosis and recovery limits.
