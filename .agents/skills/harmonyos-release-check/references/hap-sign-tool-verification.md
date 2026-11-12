# Read-only `hap-sign-tool` verification

## Locate tools safely

Start with a user-supplied DevEco root or the read-only environment probe. Search only the active installation's SDK/tool directories for `hap-sign-tool.jar`. Use `Get-Command java` or the active DevEco JBR containing `bin\java.exe`. Do not recursively scan unrelated user directories.

## Confirm local syntax

The tool is version-sensitive. Before constructing the command, run the local JAR's general help and command help. Do not assume flags from a different SDK release.

The OpenHarmony hapsigner interface defines `verify-app` with an input file, output certificate chain, and output profile. A typical shape is:

```powershell
$verifyRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("harmony-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $verifyRoot | Out-Null
& <java-exe> -jar <hap-sign-tool.jar> verify-app -inFile <final-app> -outCertChain (Join-Path $verifyRoot 'cert-chain.cer') -outProfile (Join-Path $verifyRoot 'profile.p7b')
```

Use only the flags confirmed by the local tool. A nonzero exit is `FAIL`, even if output files exist.

## Validate evidence

1. Compute a SHA-256 digest of the exact final APP before and after verification.
2. Confirm `verify-app` succeeds and creates the requested outputs.
3. Use the local tool's `verify-profile` help to write profile verification results to a temporary JSON file rather than the console when supported.
4. Inspect only the fields needed to compare expected profile type, bundle, validity, and identity. Redact sensitive values from reports.
5. Inspect the certificate chain with an available certificate tool and compare against the expected authorized identity. Report match/mismatch, not the real fingerprint.
6. Combine Release build-mode evidence with Release profile and certificate evidence. File naming alone cannot prove Release.

The official OpenHarmony [hapsigner repository](https://gitee.com/openharmony/developtools_hapsigner) is the primary command-interface reference. Huawei's [application package glossary](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/application-package-glossary) explains the final APP package role. Prefer the active SDK's tool help when it differs.

Delete temporary verification outputs after the report is safely recorded, subject to the user's evidence-retention policy.
