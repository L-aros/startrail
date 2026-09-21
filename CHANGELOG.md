# Changelog

遵循 Keep a Changelog 与语义化版本。

## [Unreleased]

### Added
- 分层实施计划与首个未完成 Milestone 验收范围。
- Proposed ADR-0005，用于审批 Milestone 1 的密码学与加密索引依赖。
- Proposed ADR-0006，用于解决 sodium 与锁定 Dart SDK 的版本不兼容。
- Proposed ADR-0007，用于解决 sodium 与 SQLCipher 原生构建钩子冲突。
- Accepted ADR-0008，并以可离线审计的单行 `vswhere -utf8` vendor 补丁修复中文 Windows 原生构建。
- Accepted ADR-0009，并实现 Vault Header v1 固定向量、严格解析与 VMK 包装。
- Accepted ADR-0010，并实现初始 Manifest、密文摘要与 HEAD v1 编码及创建事务。
- Accepted ADR-0011，并实现 SQLCipher 派生索引 Schema v1、generation 校验、成组隔离与失败安全重建。
- Accepted ADR-0012，用于避免 SQLCipher key 进入不可清零的 Dart String。
- Accepted ADR-0013，并以可复现 SQLCipher 4.16.0 源码构建导出 raw-key API；Android APK 链接固定 OpenSSL 3.6.2 静态库。
- Accepted ADR-0014，并限定 native_toolchain_c 仅对 `vswhere -utf8` 输出使用显式 UTF-8 解码。
- Accepted ADR-0015，并实现平台 Vault 路径 adapter、密码字节清理与隔离的 Vault session worker。
- Android/Windows Flutter 工程及 domain/application/infrastructure/design_system 分层骨架。
- canonical JSON 与 STOB v1 envelope 严格编解码及协议测试。
- WSL 原生构建路径和 SQLCipher 运行时身份验证测试。
- 临时文件 flush、原子替换、回滚恢复协调器及 POSIX/Windows 目录持久化 adapter。
- 创建、打开、错误密码、锁定 UI 与 Android/Windows 正式中文品牌。
- Accepted ADR-0016，并实现条目对象协议（entry/tombstone payload v1）、标签/附件内嵌、manifest 更新事务、加密搜索（search_ciphertext 与标签密文列）。
- 领域层 Entry/Tag/Attachment 值对象与 EntryStore 端口、应用层 EntryService 用例与稳定错误码映射。
- 基础设施 VaultEntryStore：对象加密落盘、manifest 父链与 HEAD 原子替换、SQLCipher 索引 CRUD、时间线倒序查询、解锁后本地搜索。
- VaultSession 会话封装与 isolate worker 扩展，支持解锁后条目 CRUD。
- 解锁后时间线 UI：按事件时间倒序浏览、本地搜索、新建/编辑/删除条目、标签（逗号分隔）。
- 附件导入：选择文件后加密为不可变 blob 对象落盘，条目内嵌附件元数据（mime、大小、digest）并支持移除。
### Changed
### Deprecated
### Removed
### Fixed
- 修复 Windows runner 中文标题受本地代码页误解码，以及顶层 Flutter 构建未继承依赖包 SQLCipher hook、可能静默链接普通 SQLite 的问题。
- 修复 Linux 目标编译 SQLCipher 时未链接 OpenSSL，导致 `libsqlite3.so` 保留未定义的 `RAND_bytes` 符号并在加载阶段失败的问题；Linux 分支现补齐 `crypto` 与 `m` 链接参数，符号闭包完整。
### Security
- 忽略本地环境配置、私钥、签名材料、仓库内 Vault 目录与明文导出，避免其被意外提交。
- 加密索引数据库、WAL、SHM 的 fixture 正文、raw key 与 key hex 泄漏扫描。
- 增加 Argon2id KEK 派生及 XChaCha20-Poly1305 对象加解密、AD 绑定和篡改失败测试。
- 增加 Vault 解锁事务、manifest v1 严格格式门禁、敏感 session 清零及错误密码/篡改回归测试。
- 增加 100 个独立密文对象往返压测及 Android/Windows 发布产物 SQLCipher 符号门禁。

## [0.0.0] - YYYY-MM-DD

### Added
- 仓库级文档基线。
