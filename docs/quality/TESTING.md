# 测试策略

| 层 | 覆盖 |
|---|---|
| 单元 | 领域规则、canonical JSON、KDF/envelope 向量、merge、错误映射 |
| 集成 | 原子 Vault 写入、SQLite 重建、导入恢复、S3 条件更新/断网/重试 |
| 端到端 | Android/Windows 创建、记录、锁定、备份、双设备同步与冲突 |
| 安全/回归 | 密文篡改、nonce 唯一、错误密码、日志红队扫描、依赖/secret 扫描 |
| UI | golden、语义树、键盘、系统字号、亮暗/高对比 |

格式和 crypto 必须有跨平台固定 fixture 与 known-answer vector；随机测试可注入确定性 RNG 仅限测试。任何 bug 先补失败测试。覆盖率是信号而非替代：domain/application 行覆盖目标 ≥80%，安全/同步分支必须覆盖。
