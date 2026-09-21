# 实施计划

本计划以「安全/协议规范 > Accepted ADR > PRD > 架构文档 > 当前代码」为约束顺序。任何里程碑不得通过降低已发布格式、加密、隐私或可恢复性要求来验收。

## Milestone 1：离线 Vault 基础

状态：**Complete**；创建/解锁/锁定 UI、平台路径 adapter 与工作 isolate session 已实现。协议级 100 对象压测、错误密码/篡改/未知格式、原子写入/回滚、SQLCipher 索引及 Flutter widget/isolate 测试通过。Android release APK 与 Windows release 构建通过；两端原生资产均验证 SQLCipher 4.16.0 和 raw-key 导出，APK 清单无网络或存储权限。

交付顺序：

1. 建立 Flutter Android/Windows 应用与 application/domain/infrastructure/design_system 分层骨架。
2. 在 ADR-0005 Accepted 后锁定密码学和加密 SQLite 依赖，补充 SBOM/许可证记录。
3. 先编写 canonical JSON、header/envelope/HEAD 解析、错误密码与篡改密文失败测试，再实现密码学 adapter。
4. 实现同卷临时文件、fsync、原子替换和创建失败回滚，注入故障验证各个持久化阶段。
5. 实现加密派生 SQLite 索引、index_generation 校验、完整性检查和从 manifest/对象重建。
6. 实现创建、解锁、锁定 UI；所有鉴权失败统一显示 VAULT_AUTH_FAILED。
7. 通过格式化、静态分析、单元/集成/篡改/崩溃恢复测试以及 Android 10+ 和 Windows 构建。

里程碑验收是 docs/quality/ACCEPTANCE.md 第 1、2、3 项中与离线 Vault 相关的部分：可创建/重启/锁定/解锁，错误密码、篡改和未知格式硬失败，写入中断不产生已确认数据丢失。“100 条与附件”的条目业务操作属于 Milestone 2，但 Milestone 1 会先用协议级测试对等量的加密对象进行压测。

## Milestone 2：条目、时间线、标签、搜索与附件

状态：**Complete**（后端 + Flutter UI 全部落地并通过 CI）。

已完成：

- Accepted ADR-0016，固定 entry/tombstone 对象 payload v1、标签/附件内嵌策略、manifest 更新事务与崩溃恢复、加密搜索方案。
- 领域层：Entry/Tag/Attachment/EntryDraft 值对象与校验规则、EntryStore 端口、EntryNotFound/EntryRevisionConflict 领域异常。
- 基础设施：object_id、EntryObjectCodec、ManifestV1Codec、SearchCipher、VaultEntryStore（对象加密落盘 → manifest 父链 → HEAD 原子替换 → 索引单事务更新）。
- 应用层：EntryService 用例、标签规范化查重、稳定错误码映射。
- 测试：领域/应用层单测通过；基础设施编解码与集成测试已编写（本地因 `reg.exe` 被安全策略黑名单阻止、无法编译 SQLCipher 原生库，待 CI 或解除黑名单后运行）。

已落地：

- Flutter 时间线、条目编辑器、标签、本地搜索、附件导入 UI；扩展 isolate worker 支持解锁后条目 CRUD。
- 附件 blob 对象的导入/管理闭环。

## Milestone 3：加密备份、隔离验证、导入与恢复

状态：**进行中**（后端完成，Flutter UI 待接续）。

已完成：

- Accepted ADR-0017，固定备份容器格式（`STBKP`）、Backup Key 密钥层级、隔离验证与事务化恢复语义；决策点「单文件认证容器 / 仅干净目标+确认替换 / 与 Vault 同密码」经用户确认。
- 格式层：`BackupHeaderCodec`（`STBKP` magic + canonical JSON + KDF 参数下限校验）、`BackupManifestCodec`（逐文件 `sha256` 清单 + 路径白名单）、容器字节布局。
- 密码学层：`BackupCrypto`（BK 包装/解包 + manifest AEAD，AD 域名分离，复用 Argon2id + XChaCha20-Poly1305）。
- `BackupCreator`/`BackupVerifier`/`BackupRestorer`：单文件认证容器、只读隔离验证（ok/wrong_password/tampered/corrupt/unsupported）、事务化恢复（完整验证→暂存提取→复验→原子交换，失败不改写目标）。
- `IndexPopulator`：从已认证对象与 manifest 重建 `entries/tags/entry_tags/attachments`，替换 `VaultSession` 的 `populate` 空占位。
- 领域层 `BackupStore` 端口与备份值对象、应用层 `BackupService` 用例与稳定 `BACKUP_*` 错误码。
- 测试：codec 固定向量与路径白名单、crypto 往返与 AD 绑定、verifier 五种状态、creator→verify→restore 字节级往返与失败注入、含条目/附件的恢复后索引重建。

待接续：

- Flutter 备份/恢复 UI（导出备份、从备份恢复、验证报告展示）与 isolate worker 消息协议扩展。

## 后续 Milestone

4. 显式启用的 R2 同步、冲突保留/解决与可取消重试。
5. 签名更新、可选遥测、平台安全存储和发布门禁。
