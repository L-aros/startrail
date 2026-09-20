# 实施计划

本计划以「安全/协议规范 > Accepted ADR > PRD > 架构文档 > 当前代码」为约束顺序。任何里程碑不得通过降低已发布格式、加密、隐私或可恢复性要求来验收。

## Milestone 1：离线 Vault 基础

状态：**Blocked by ADR-0009 approval**；密码学原语与对象 envelope 已完成，Vault Header v1 精确编码需审批后实现。Windows 最终构建仍等待 ADR-0008 决策。

交付顺序：

1. 建立 Flutter Android/Windows 应用与 application/domain/infrastructure/design_system 分层骨架。
2. 在 ADR-0005 Accepted 后锁定密码学和加密 SQLite 依赖，补充 SBOM/许可证记录。
3. 先编写 canonical JSON、header/envelope/HEAD 解析、错误密码与篡改密文失败测试，再实现密码学 adapter。
4. 实现同卷临时文件、fsync、原子替换和创建失败回滚，注入故障验证各个持久化阶段。
5. 实现加密派生 SQLite 索引、index_generation 校验、完整性检查和从 manifest/对象重建。
6. 实现创建、解锁、锁定 UI；所有鉴权失败统一显示 VAULT_AUTH_FAILED。
7. 通过格式化、静态分析、单元/集成/篡改/崩溃恢复测试以及 Android 10+ 和 Windows 构建。

里程碑验收是 docs/quality/ACCEPTANCE.md 第 1、2、3 项中与离线 Vault 相关的部分：可创建/重启/锁定/解锁，错误密码、篡改和未知格式硬失败，写入中断不产生已确认数据丢失。“100 条与附件”的条目业务操作属于 Milestone 2，但 Milestone 1 会先用协议级测试对等量的加密对象进行压测。

## 后续 Milestone

2. 条目 CRUD、时间线、标签、搜索与附件。
3. 加密备份、隔离验证、导入与恢复。
4. 显式启用的 R2 同步、冲突保留/解决与可取消重试。
5. 签名更新、可选遥测、平台安全存储和发布门禁。
