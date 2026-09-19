# CLAUDE.md — 实施导航

开始任何工作前阅读：`AGENTS.md` → `docs/architecture/ARCHITECTURE.md` → 所在领域文档。实现分层为 `presentation → application → domain ← infrastructure`；依赖箭头只能向内。

## 推荐交付顺序

1. Vault 创建/解锁、加密对象读写与本地 SQLite 索引；2. 条目 CRUD、时间线、附件；3. 导入/导出与恢复；4. R2 同步与冲突界面；5. 更新、遥测与平台细节。

## 不可猜测的决定

- 密码派生、算法参数、对象字段和冲突规则以 `docs/security/CRYPTOGRAPHY.md`、`docs/sync/OBJECT_FORMAT.md` 为准，不自行替换。
- 产品范围以 PRD 为准；UX 以 `docs/ui/` 为准。
- 发现文档矛盾：停止在该边界继续实现，提出 ADR；不得“选择看起来合理的一边”。

## AI 规则

AI 可生成样板、测试、文档和本地代码；不得访问真实 Vault、使用真实用户内容作为提示词、自动安装未审查依赖、自动上传、自动发布，或通过模糊化来隐藏数据流。每个生成改动都要可审阅、可复现且受测试覆盖。详见 `docs/development/AI_RULES.md`。
