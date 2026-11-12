# AppGallery test-channel validation

## Purpose and scope

Use this guide after independent artifact verification and before or during device smoke testing of a Release candidate. AppGallery channel behavior is platform- and account-policy-sensitive: verify the currently available channel and platform requirements from the authorized console or official guidance. This guide does not authorize upload, submission, or publication.

## Channel-first diagnosis

When a device install fails, first record the candidate's signing/distribution type and the requested installation channel. Decide whether that identity is permitted on the channel before investigating the APP as a signing or build failure.

In particular, a device-side signature-verification message can indicate a channel-policy mismatch. It is not, by itself, conclusive evidence that the final APP is corrupted. Only after channel restrictions have been ruled out should the failure be escalated to package verification, signing, or build investigation.

## Release-signed candidate testing paths

After `ARTIFACT_VERIFIED`, select exactly one traceable path:

1. If the candidate is permitted on a direct development or local-install channel, install that exact artifact and perform the human smoke test.
2. If a formal AppGallery release identity is not permitted, or should not be used, through direct installation, obtain explicit user authorization before staging the unchanged verified candidate in a supported pre-release AppGallery test channel. Wait for the platform's required acceptance checks, install through that channel, then perform the human smoke test.

Pre-release AppGallery test-channel staging is only for testing. It neither constitutes formal submission/production publication nor weakens the separate publication-authorization gate. Invitation testing can be limited to a test group; public/open testing can be visible to broader or public testers. Both remain test distribution before formal production publication. Verify current channel availability and visibility in AppGallery Console or official rules.

## Separate AppGallery status evidence

Track each status independently:

| Status | What it proves | What it does not prove |
| --- | --- | --- |
| Upload accepted | The platform accepted the upload request | Package legality, test availability, listing readiness, or publication |
| Package legality / parsing accepted | The required package processing completed | Listing self-check, test availability, or publication |
| Pre-release / listing self-check | The platform has evaluated the applicable pre-release checks | Invitation/open testing or formal publication |
| Invitation / open testing | Authorized testers can install the identified candidate through that channel | Formal submission or publication |
| Formal submission / publication | A separately authorized formal release process has reached its recorded state | Completion of unrelated gates or implicit authorization |

Never collapse these states into one overall PASS. For example, legality/parsing acceptance while listing self-check is still running is not `READY_FOR_PUBLICATION`.

## Exact-artifact identity

The final candidate identity is the tuple of commit, versionName, versionCode, platform buildVersion when present, and final APP SHA-256. Record that tuple before upload, preserve it through channel testing, and attach it to the smoke-test result. A filename, version label, or upload timestamp alone is insufficient.

If the candidate changes, including through re-signing or rebuilding, it is a different candidate. Re-enter verification and testing for the new identity rather than inheriting evidence from the prior one.

## HDC failure anti-patterns and forbidden recovery

Do not follow this default chain: failed HDC install, assumed damaged signature, re-sign, uninstall the installed formal app, rebuild the candidate. Instead, diagnose the channel first and retain the original candidate evidence while the cause remains ambiguous.

Without explicit user authorization, do not uninstall a device's formal application. Do not automatically re-sign, rebuild, or otherwise mutate the final candidate to diagnose a failure that channel policy may explain. Do not infer package damage solely from a device-side signature-verification error.

## Human and instrumented performance evidence

Human smoke testing may assess whether interaction has visibly blocking pauses, whether a page begins responding immediately, and whether repeated navigation causes wrong pages, black screens, crashes, duplicate routing, or state desynchronization. Record an experience-level pass/fail observation.

Do not require a human smoke tester to provide millisecond latency. Obtain timing and frame-level evidence from automated performance checks, a profiler, logs or traces, or frame analysis.

## Minimal escalation strategy

1. Preserve the verified candidate and its identity evidence.
2. Classify the signing/distribution policy and intended install channel.
3. If the channel is incompatible, ask only for the needed user authorization to stage the unchanged candidate in a supported pre-release AppGallery test channel; do not imply publication approval.
4. If the platform's required acceptance stage is incomplete, report that specific status as `BLOCKED` and wait for it.
5. Escalate to signing/build investigation only after channel restrictions are excluded or independent verification fails.
