# Git 工作流

`main` 始终可发布；短生命周期分支 `feat/`、`fix/`、`docs/`。一次提交只含一个目的，使用 Conventional Commits（`feat:`、`fix:`、`docs:`、`test:`、`chore:`、`security:`）。PR 需要 CI、至少一位审阅者；安全/格式/依赖/更新改动需要额外所有者审阅。

禁止重写已发布 tag、提交密钥或生成 Vault。发布 tag 使用 `vMAJOR.MINOR.PATCH`，生成可追溯构建、SBOM、签名和 CHANGELOG。紧急修复从 release tag 分支，补回 main。
