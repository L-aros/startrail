# 架构

```text
Flutter presentation ── application use cases ── domain ports
                                                ├─ local Vault adapter (FS + SQLite)
                                                ├─ crypto adapter
                                                ├─ R2/S3 sync adapter
                                                └─ platform adapter (secure storage, files, updater)
```

每个 Vault 是独立根目录，所有用户可读数据先加密后落盘；SQLite 是可重建的本地派生索引，权威数据是加密的 append-only 条目对象与 manifest。`VaultRepository` 负责事务与恢复；`SyncEngine` 只看密文对象和加密 manifest；UI 经用例获得状态，不可越层。

## 核心不变量

1. 内容对象以不可变内容 ID 命名；不覆盖内容对象。
2. manifest 是唯一可变逻辑头指针，但以不可变版本对象 + 条件更新发布。
3. 本地数据库损坏可由对象重建；对象损坏不能由数据库掩盖。
4. 一个逻辑实体的并发版本保留为 sibling，绝不按时间戳静默覆盖。

详见 `PROJECT_STRUCTURE.md`、`docs/sync/` 和 `docs/security/`。
