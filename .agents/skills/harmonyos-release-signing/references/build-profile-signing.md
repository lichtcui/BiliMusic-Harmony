# Signing configuration model

Project-level `build-profile.json5` commonly associates an app's `signingConfigs` with an entry in `products` through `products.<product>.signingConfig`. Exact schema details vary by DevEco Studio and SDK version; treat the active project's generated schema and local tool help as authoritative.

Audit these fields by presence and boundary, not by printing values:

| Field | Safe question |
| --- | --- |
| `keyAlias` | Is the expected Release key selected? |
| `certpath` | Is the authorized Release certificate outside Git and readable? |
| `profile` | Is the authorized Release profile outside Git and readable? |
| `storeFile` | Is the keystore outside Git and not staged/tracked? |
| `storePassword` | Is the field safely classified without disclosure? |
| `keyPassword` | Is the field safely classified without disclosure? |

Sanitized shape:

```json5
{
  app: {
    signingConfigs: [
      {
        name: "release-local",
        type: "HarmonyOS",
        material: {
          certpath: "<outside-repository>/release.cer",
          storeFile: "<outside-repository>/release.p12",
          profile: "<outside-repository>/release.p7b",
          keyAlias: "<release-key-alias>",
          storePassword: "<managed-secret>",
          keyPassword: "<managed-secret>"
        }
      }
    ],
    products: [{ name: "default", signingConfig: "release-local" }]
  }
}
```

This is a shape example, not a portable config. Do not copy its names as real identities.

## Classification procedure

1. Inspect whether the value is absent/empty without logging it.
2. Recognize obvious environment/reference placeholders as `UNDETERMINED` until resolved by the build environment.
3. Ask the active DevEco tooling to validate/decrypt through its normal build flow when safe; do not echo the value.
4. Treat a known DevEco ciphertext structure as `LIKELY` until tool validation confirms it.
5. Treat an ordinary literal as `PLAINTEXT_LIKELY` only when there is positive evidence and it is not an explicit example.
6. If evidence conflicts, use `UNDETERMINED` and stop.

Huawei documents product/build-mode selection in the official [Hvigor build mode example](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/ide-hvigor-compilation-options-customizing-sample-V14). Always verify current local syntax.
