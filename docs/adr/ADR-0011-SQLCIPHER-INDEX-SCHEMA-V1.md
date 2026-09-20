# ADR-0011：SQLCipher 派生索引 Schema v1

- 状态：Proposed
- 日期：2026-09-20
- 决策范围：数据库 Schema、索引密钥使用、迁移与损坏恢复

## 背景

数据库规范列出最小表，但没有固定列类型、约束、`index_generation` 来源、SQLCipher PRAGMA 顺序或损坏隔离命名。Manifest v1 也没有独立 `index_generation` 字段。若直接实现，会造成平台间 Schema 漂移，或为索引 generation 修改已接受的 manifest 协议。

SQLite 索引只是可重建派生数据，不得成为权威来源；任何失败必须保留原数据库用于诊断/回滚，同时从已认证对象重建。

## 提议

### Generation 语义

- 不修改 Manifest v1。
- `index_generation` 定义为构建索引时使用的、已经 HEAD/digest/AEAD 验证的 `manifest_id`。
- 数据库 `index_meta` 单行保存该值。打开后若与当前 HEAD 的 `manifest_id` 不同，关闭并隔离数据库，然后全量重建。

### SQLCipher 密钥

- 继续采用 ADR-0005：从 VMK 通过 `crypto_kdf_derive_from_key` 派生 32 bytes，context 为 8-byte ASCII `STIDX001`，subkey id 为 `1`。
- 打开数据库后，任何 Schema/元数据查询前先设置 raw 32-byte key，再读取 `PRAGMA cipher_version`；结果为空立即拒绝。
- key 只在打开数据库期间通过 `SecureKey` 解锁回调提供，PRAGMA 执行后清除临时 hex buffer；禁止日志、异常文本或 SQL trace。
- 索引关闭时释放派生 key。

### 固定 PRAGMA

每次连接按顺序应用：

1. raw key；
2. `cipher_memory_security = ON`；
3. 验证 `cipher_version` 非空；
4. `foreign_keys = ON`；
5. `trusted_schema = OFF`；
6. `secure_delete = ON`；
7. `journal_mode = WAL`；
8. `synchronous = FULL`。

打开既有索引时运行 `cipher_integrity_check` 与 `quick_check(1)`；两者必须只返回 `ok`。

### Schema v1

设置：

- `PRAGMA application_id = 0x53544958`（ASCII `STIX`）；
- `PRAGMA user_version = 1`。

所有时间为 RFC 3339 UTC TEXT；布尔/枚举使用带 CHECK 的 INTEGER/TEXT；外键启用。

```sql
CREATE TABLE index_meta (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  manifest_id TEXT NOT NULL CHECK (length(manifest_id) = 52)
) STRICT;

CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL CHECK (revision >= 0),
  occurred_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'deleted')),
  search_ciphertext BLOB NOT NULL
) STRICT;

CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  name_ciphertext BLOB NOT NULL,
  normalized_name_ciphertext BLOB NOT NULL UNIQUE,
  color INTEGER NOT NULL CHECK (color BETWEEN 0 AND 4294967295)
) STRICT;

CREATE TABLE entry_tags (
  entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (entry_id, tag_id)
) STRICT, WITHOUT ROWID;

CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  blob_id TEXT NOT NULL CHECK (length(blob_id) = 52)
) STRICT;

CREATE TABLE sync_state (
  remote_id TEXT PRIMARY KEY,
  head_id TEXT,
  cursor TEXT,
  last_success_at TEXT
) STRICT;

CREATE TABLE conflicts (
  id TEXT PRIMARY KEY,
  entity_id TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('unresolved', 'resolved'))
) STRICT;

CREATE TABLE outbox (
  object_id TEXT PRIMARY KEY CHECK (length(object_id) = 52),
  priority INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0)
) STRICT;
```

索引：`entries(updated_at)`、`entries(occurred_at)`、`attachments(entry_id)`、`conflicts(entity_id, state)`、`outbox(priority DESC, attempts ASC)`。

### 创建、迁移与隔离

- 新数据库在单个 `BEGIN IMMEDIATE` 事务内创建全部表、索引、meta、`application_id` 和 `user_version`；失败删除未发布临时数据库。
- v1 不接受 `user_version = 0` 的非空未知数据库，也不就地猜测 Schema。
- 未来迁移必须逐版本、事务化、可重复测试，并仅修改派生索引。
- 密钥错误、SQLCipher 缺失、完整性失败、application/user version 不匹配或 generation 不匹配时，关闭连接，将 `index.db`、`-wal`、`-shm` 作为一组移动到 `local/quarantine/<UTC timestamp>-<random>/`，同步目录，然后从当前已认证 manifest/对象重建。
- 隔离文件名和路径不得写日志或遥测。

## 安全与兼容性影响

- 本 ADR 固化本地派生 Schema，但不改变 Vault、对象、manifest、HEAD 或同步协议。
- SQLCipher raw-key PRAGMA 不能使用普通 SQL 参数绑定；实现必须限定为固定模板与内部生成的 lowercase hex，并禁止 trace。其余 SQL 必须参数化。
- WAL/SHM 与主库同等敏感，备份、隔离和清理必须成组处理。
- `search_ciphertext` 与 tag 密文字段不得退化为明文搜索内容。

## 验证要求

- 固定 VMK 的 KDF 测试向量：context/subkey/output 精确匹配。
- `cipher_version` 非空；普通 SQLite 与错误 key 无法读取 Schema。
- 数据库/WAL/SHM 字节扫描不出现 fixture 正文明文。
- v1 创建事务、约束、外键、索引、application/user version 测试。
- generation、完整性、密钥或版本失败均成组隔离并可从 fixture manifest 重建。
- 强制终止创建/重建不会替换最后一个可用索引，也不修改权威对象。

## 备选方案

- 在 manifest 新增 `index_generation`：改变已接受协议且值可由 manifest ID 唯一表达，拒绝。
- 明文 SQLite 加字段级加密：容易遗漏页、WAL、临时数据和查询结果，拒绝。
- generation 不匹配时就地增量修补：扩大恢复复杂度并可能保留过期派生状态，v1 拒绝。
