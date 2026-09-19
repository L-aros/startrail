# 技术栈与约束

| 层 | 选择 | 约束 |
|---|---|---|
| 客户端 | Flutter stable + Dart stable | 锁定 SDK；Android/Windows 同一业务代码 |
| 本地索引 | SQLite（SQLCipher 或整个 DB 加密封装） | 仅派生数据；数据库也须静态加密 |
| 密码学 | 成熟、审计过的 Dart/原生库 | 不自研算法；见 CRYPTOGRAPHY |
| 同步 | Cloudflare R2 S3 兼容 API | 仅客户端密文、最小权限凭据 |
| 状态/DI | 可替换的轻量方案 | 状态不可持有明文秘密超过必要生命周期 |
| CI | GitHub Actions 或等价可审计 CI | 运行测试、SBOM、依赖/密钥扫描、签名构建 |

具体库在实现 ADR 后锁定。禁止添加闭源追踪 SDK、未维护 crypto 库或要求服务端明文的 BaaS。
