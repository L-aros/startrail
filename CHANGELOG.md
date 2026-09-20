# Changelog

遵循 Keep a Changelog 与语义化版本。

## [Unreleased]

### Added
- 分层实施计划与首个未完成 Milestone 验收范围。
- Proposed ADR-0005，用于审批 Milestone 1 的密码学与加密索引依赖。
- Proposed ADR-0006，用于解决 sodium 与锁定 Dart SDK 的版本不兼容。
- Proposed ADR-0007，用于解决 sodium 与 SQLCipher 原生构建钩子冲突。
- Proposed ADR-0008，用于修复 sodium 在中文 Windows 上解析 vswhere 输出失败。
- Accepted ADR-0009，并实现 Vault Header v1 固定向量、严格解析与 VMK 包装。
- Accepted ADR-0010，并实现初始 Manifest、密文摘要与 HEAD v1 编码及创建事务。
- Android/Windows Flutter 工程及 domain/application/infrastructure/design_system 分层骨架。
- canonical JSON 与 STOB v1 envelope 严格编解码及协议测试。
- WSL 原生构建路径和 SQLCipher 运行时身份验证测试。
- 临时文件 flush、原子替换、回滚恢复协调器及 POSIX 目录 fsync adapter。
### Changed
### Deprecated
### Removed
### Fixed
### Security
- 增加 Argon2id KEK 派生及 XChaCha20-Poly1305 对象加解密、AD 绑定和篡改失败测试。

## [0.0.0] - YYYY-MM-DD

### Added
- 仓库级文档基线。
