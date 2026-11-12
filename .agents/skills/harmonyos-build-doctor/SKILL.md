---
name: harmonyos-build-doctor
description: Diagnose HarmonyOS and DevEco Studio command-line build failures involving Node, NODE_HOME, DEVECO_SDK_HOME, SDK components, Java, JAVA_HOME, Hvigor, hdc, or hap-sign-tool. Use when the IDE works but hvigorw fails in a shell, or before reinstalling/upgrading tools or changing application code for a build startup failure.
---

# HarmonyOS Build Doctor

## Scope

Diagnose the environment before changing the application. Prefer the runtime and SDK bundled with the active DevEco Studio installation over installing a second toolchain.

## Use when

Use when DevEco Studio works but a shell build fails, or when Node, SDK, Java, Hvigor, wrapper, daemon, or tool-root evidence prevents the build from reaching application compilation.

## Do not use when

Do not use to fix business ArkTS logic, configure Release signing, verify a final APP, or authorize publication.

## Handoff

When the environment issue is resolved and the retry exposes a compile or dependency error, close the original diagnosis and hand off the new evidence as a separate problem. Do not edit application code without separate authorization.

## Required inputs

- Project root and exact failing command.
- Complete first causal error plus final exit code.
- Shell type and whether the same task works inside DevEco Studio.
- Known DevEco Studio location or version, if available.

## Workflow

1. Preserve the original failure. Record the command, working directory, exit code, and first causal error without secrets.
2. Run the [bundled read-only probe](scripts/check-deveco-env.ps1):

   ```powershell
   .\scripts\check-deveco-env.ps1 -ProjectPath <project-root> -Json
   ```

3. Read [the decision tree](references/decision-tree.md) and select the first matching layer. Do not skip ahead to reinstall or code changes.
4. Verify a candidate executable or SDK directory exists and is structurally valid before use.
5. If a bundled component is valid, set environment variables only in the current process and retry the exact original command.
6. Stop the Hvigor daemon when switching SDK or Java roots, using the locally supported `--stop-daemon` form discovered from wrapper help.
7. Compare the retry with the original failure. Advance to the next layer only if the causal error changed.
8. Mark the prior layer `RESOLVED` when its causal error disappears. Reclassify the replacement failure from fresh evidence; never carry the old diagnosis forward.
9. Return the evidence contract below.

Use [environment evidence](references/environment-evidence.md) to interpret `FOUND`, `NOT_FOUND`, `INVALID`, and `UNKNOWN`.

## Decision rules

- **Node unavailable:** check `Get-Command node`, `NODE_HOME`, then the active DevEco root's `tools\node\node.exe`; verify its version; temporarily prepend it to `PATH`; retry.
- **SDK missing/invalid:** inspect Process, User, and Machine `DEVECO_SDK_HOME`; check the active DevEco SDK; verify required API/components; set only the process value; stop the daemon; retry.
- **`spawn java ENOENT`:** check `Get-Command java` and `JAVA_HOME`; prefer the active DevEco JBR containing `bin\java.exe`; set `JAVA_HOME` and process `PATH`; stop the daemon; retry.
- If the command reaches ArkTS compilation after an environment change, reclassify any new error from fresh evidence; do not retain the original environment diagnosis automatically.
- **Multiple DevEco installations:** never select the newest automatically. Prefer project configuration, the IDE active path, wrapper/tool evidence, or a human-supplied path. If these cannot identify one root, report `BLOCKED_AMBIGUOUS_DEVECO`.

## Stop conditions

Stop when the active DevEco installation cannot be identified, multiple plausible SDKs cannot be disambiguated, a required SDK API/component is absent, the project requests an incompatible tool version, or the next action would persist machine state. Report the exact missing evidence.

## Forbidden actions

- Do not use `setx` or modify User/Machine environment variables.
- Do not reinstall or upgrade Node, JDK, SDK, DevEco Studio, or Hvigor before verifying bundled components.
- Do not modify application or business code to fix an environment startup error.
- Do not scan unrelated user directories or print environment secrets.
- Do not claim success unless the original command is rerun and its result recorded.

## Output contract

Return:

- **Original failure** — command category, exit code, first causal error.
- **Environment evidence** — component, status, safe path/source description, version or structural check.
- **Classification** — Node, SDK, Java, Hvigor, project configuration, compile, or unresolved.
- **Process-only action** — exact variables changed, with credential values omitted.
- **Retry result** — exact task, exit code, changed/unchanged error, completed stages.
- **Next minimal action** — one step, or `none` if resolved.

Optionally append redacted JSON conforming to the repository's [evidence schema](https://github.com/zhangifexim-bit/harmonyos-agent-skills/blob/main/schemas/evidence.schema.json). Use `persistent_changes: false`; paths should be redacted categories, not personal absolute paths.

## Validation

Confirm User/Machine environment values are unchanged. Confirm the target project's source diff is unchanged unless the user separately authorized a code fix. Confirm the retry used the original task and product/module parameters.
