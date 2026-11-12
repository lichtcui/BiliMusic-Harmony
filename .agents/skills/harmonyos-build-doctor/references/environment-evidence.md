# Environment evidence schema

The probe reports one row per component:

- `FOUND`: a candidate exists and its minimal executable/structure check passed.
- `NOT_FOUND`: bounded searches found no candidate.
- `INVALID`: a configured or discovered candidate exists but failed validation.
- `UNKNOWN`: evidence is insufficient or validation could not run safely.

Expected components are DevEco Studio, Node, SDK, JBR/Java, Hvigor, hdc, and hap-sign-tool.

Paths are diagnostic evidence, not portable configuration. Do not copy discovered personal paths into source, docs, patches, or prompts. Prefer passing an explicit `-DevEcoPath` when the installation is nonstandard.

DevEco Studio's integrated terminal can supply IDE-managed environment values; an external shell may not inherit them. Compare scopes before treating that difference as a project defect. See Huawei's current [Terminal environment variable guidance](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-environment-variable).
