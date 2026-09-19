# StarTrail / 拾星迹

> 拾起散落的成长痕迹。

**StarTrail** 是仓库代号；面向用户的正式中文名是 **拾星迹**。这是一个 Flutter（Android + Windows）本地优先的个人成长记录应用：用户把文本、媒体与结构化记录保存在自己控制的加密 Vault 中，可选择以 Cloudflare R2 作为不可信对象存储进行端到端加密同步。

## 文档入口

| 目标 | 文档 |
|---|---|
| 产品边界与验收 | [PRD](docs/product/PRD.md) |
| 开发者操作约束 | [AGENTS.md](AGENTS.md)、[CLAUDE.md](CLAUDE.md) |
| 架构与同步 | [架构](docs/architecture/ARCHITECTURE.md)、[R2 同步](docs/sync/R2_SYNC.md) |
| 数据与加密 | [数据模型](docs/data/DATA_MODEL.md)、[Vault 格式](docs/security/VAULT_FORMAT.md)、[加密](docs/security/CRYPTOGRAPHY.md) |
| 实施与质量 | [开发环境](docs/development/DEVELOPMENT.md)、[测试](docs/quality/TESTING.md) |

## 非目标（v1）

- 不提供服务端账户、社交、协作或明文云端搜索。
- 不将任何用户内容、Vault 密钥或稳定设备标识发送给项目运营方。
- 不以 R2 配置为应用内默认凭据；用户必须自带兼容 S3 的受限凭据或预签名同步端点。
- 不承诺跨设备实时协作；同步是显式、可恢复、最终一致的。

## 快速开始

实现仓库建立后，按 `docs/development/DEVELOPMENT.md` 初始化 Flutter 工程和工具链；先通过 `docs/quality/ACCEPTANCE.md` 中的离线 Vault 场景，再接入同步。任何格式、加密或同步行为变动先走 `docs/adr/ADR_POLICY.md`。

## 状态与许可证

此包是开发基线，不含应用实现。许可证尚未决定，详见 [LICENSE-DECISION.md](LICENSE-DECISION.md)；在决定前不得宣称项目已开源或接受带许可证污染风险的贡献。
