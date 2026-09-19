# 本地数据库

SQLite 保存经加密的派生索引和 UI 状态，不是权威来源。启动时以 Vault 的 `index_generation` 验证；不匹配、完整性检查失败或解密失败则隔离旧库、从 manifest/对象重建。

## 最小表

`entries(id PK, revision, occurred_at, updated_at, status, search_ciphertext)`；`entry_tags(entry_id, tag_id)`；`attachments(id PK, entry_id, blob_id)`；`sync_state(remote_id, head_id, cursor, last_success_at)`；`conflicts(id PK, entity_id, state)`；`outbox(object_id, priority, attempts)`。

所有迁移必须事务化、可重复执行、有从前一版本的 fixture 测试；迁移只变本地索引，不得直接重写权威对象。SQL 参数化；不得把用户输入拼入 SQL 或 FTS 查询。
