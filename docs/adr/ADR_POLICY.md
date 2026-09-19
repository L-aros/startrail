# ADR 规则

ADR 编号不可复用，存于本目录 `ADR-XXXX-短名.md`。每份包含：状态、日期、背景、决策、备选、后果、迁移/回滚、测试与安全/隐私影响。状态：Proposed、Accepted、Superseded、Deprecated。

以下是**高风险变更**，必须在编码/发布前获得 Accepted ADR、兼容方案与版本化测试：Vault/对象/manifest/HEAD 格式；KDF/AEAD/AD/密钥层级；同步冲突/删除/GC；远端权限与数据流；更新信任根；平台最低版本；遥测字段；许可证；任何不可逆迁移。格式变动不得复用旧版本号；读旧写新或显式只读失败必须可预测。
