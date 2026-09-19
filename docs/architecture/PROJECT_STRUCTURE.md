# 建议项目结构

```text
startrail/
  apps/startrail_flutter/        # Flutter app、平台 runner
  packages/domain/               # 实体、值对象、端口；零 Flutter/IO
  packages/application/          # 用例、命令、状态协调
  packages/infrastructure/       # vault/crypto/sqlite/r2/平台 adapters
  packages/design_system/        # token、组件、主题
  test/ unit/ integration/ e2e/ fixtures/
  docs/                          # 本文档包内容
  tools/                         # 可复现检查、格式验证、SBOM
```

依赖仅允许 `app → application → domain` 和 `app → infrastructure`（经端口注入）；`infrastructure → domain` 可以；domain 不反向依赖。平台通道放在 app/infrastructure 边缘，禁止泄漏到领域模型。
