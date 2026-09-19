# 核心流程

## 创建与解锁

创建：确认密码 → CSPRNG VMK/salt → 写入认证 header → 建初始空 manifest/HEAD → 建加密索引。解锁：解析 header → Argon2id → 解包 VMK → 验证 HEAD/manifest → 打开索引。任一认证失败都显示同一“无法解锁”提示，避免 oracle。

## 保存条目

编辑器保留本地未加密草稿于内存；用户保存时校验 → canonical JSON → 加密不可变对象 → 原子落盘 → 写新 manifest 与 HEAD → 单事务更新索引/outbox。崩溃恢复应发现未引用临时文件并清理，或发现已落盘对象但未更新 HEAD 时保守地丢弃/提示恢复，绝不伪造成功。

## 导入、导出、恢复

导出是完整 Vault 目录的打包副本（仍加密），生成 manifest digest 报告；导入先在隔离目录验证全部 header/manifest/对象，再让用户确认替换或新建。恢复不覆盖活动 Vault，直到验证通过且用户确认。
