# DevEco CLI build decision tree

## 0. Which DevEco installation is active?

When multiple installations are present, do not sort by version and choose the newest. Resolve the active root from project configuration, IDE-active path evidence, wrapper/tool provenance, or a human-supplied path. Conflicting or insufficient evidence produces `BLOCKED_AMBIGUOUS_DEVECO`.

## 1. Can the selected Node start Hvigor?

Evidence:

- `Get-Command node -ErrorAction SilentlyContinue`
- `NODE_HOME` at Process/User/Machine scope
- `<DevEcoRoot>\tools\node\node.exe --version`
- project wrapper or `<DevEcoRoot>\tools\hvigor\bin\hvigorw.js`

If the shell has no usable Node and the active DevEco installation has a valid bundled Node, prefer that binary. Set only the current process:

```powershell
$env:NODE_HOME = '<DevEcoRoot>\tools\node'
$env:PATH = "$env:NODE_HOME;$env:PATH"
```

Retry the original command. Do not install Node immediately.

## 2. Does Hvigor reject SDK configuration?

Inspect `DEVECO_SDK_HOME` at all scopes, but change only Process scope. A directory's existence is insufficient: verify expected SDK families/toolchains and the API required by project configuration.

```powershell
$env:DEVECO_SDK_HOME = '<validated-sdk-root>'
```

Stop the existing daemon using the wrapper's local help, then retry. If the required component is absent, report `INVALID` or `NOT_FOUND`; do not modify the project or reinstall the SDK automatically.

## 3. Does packaging report `spawn java ENOENT`?

Evidence:

- `Get-Command java -ErrorAction SilentlyContinue`
- `JAVA_HOME` at Process/User/Machine scope
- `<DevEcoRoot>\jbr\bin\java.exe -version`

If the bundled JBR is valid:

```powershell
$env:JAVA_HOME = '<DevEcoRoot>\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
```

Stop the daemon and retry the original task. Do not reinstall a JDK first.

## 4. Did the failure move into project configuration or compilation?

Once Node, SDK, and Java evidence is valid, classify the new causal error independently:

- product/build mode/module mismatch;
- missing SDK component for the configured API;
- dependency resolution;
- ArkTS compile error;
- signing configuration;
- packaging or artifact verification.

An environment repair is successful only when it removes the environment error. It does not prove the application is correct.

The transition record must explicitly mark the prior issue `RESOLVED`, include the new classification, and avoid reusing the original diagnosis.
