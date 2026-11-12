# Risk classification

| Level | Examples | Default action |
| --- | --- | --- |
| Low | Read files, inspect Git state, parse local configuration with redaction | Proceed read-only |
| Moderate | Focused source edit, local test, generated build output | Require Gate B authorization; preserve unrelated work |
| High | Signing configuration, credentials, permissions, schema/data migration, device data, persistent environment changes | Stop and request explicit scope plus rollback/verification plan |
| Publication | Commit, push, tag, release, visibility change, store upload | Require explicit authorization for each external boundary |

Escalate any action whose target is ambiguous, whose rollback is unclear, or whose output may contain private material. When a safer read-only action can establish the missing fact, take it first.
