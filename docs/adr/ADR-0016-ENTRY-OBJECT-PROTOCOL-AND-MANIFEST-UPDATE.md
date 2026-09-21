# ADR-0016：条目对象协议与 Manifest 更新事务 v1

- 状态：Accepted
- 日期：2026-09-21
- 决策范围：Entry/Tombstone/Blob 对象 payload、标签与附件表示、manifest 更新事务与崩溃恢复、加密搜索

## 背景

Milestone 2 需要实现条目 CRUD、时间线、标签、搜索与附件。现有规范固化了对象 wrapper 与 manifest 结构，但存在以下空白，直接编码会导致平台间不兼容或破坏已发布格式：

1. `OBJECT_FORMAT.md` 只定义 wrapper `{kind,id,revision,device_id,created_at,payload}`，未定义 `entry`、`tombstone` 的 `payload` 字段集合。
2. `kind` 枚举只有 `entry`、`tombstone`、`attachment-meta`、`manifest`，没有 `tag`；标签的权威数据如何随对象重建未定义。
3. `DATA_MODEL.md` 把 `status` 列为 Entry 字段，但架构以 tombstone 表达删除；两者如何调和未定义。
4. `CORE_FLOWS.md` 描述「保存条目」的流程方向，但 manifest 更新事务顺序、HEAD 原子替换、崩溃恢复与孤儿清理未明确。
5. `ADR-0011` 固化了 `search_ciphertext`、`name_ciphertext`、`normalized_name_ciphertext` 列，但未定义其生成与使用方式；搜索必须满足「仅在解锁后本地索引」且不得退化为明文。

## 提议

### 1. Entry 对象（kind=entry，plaintext schema version=1）

明文是 canonical JSON，wrapper 不变：

```json
{
  "kind": "entry",
  "id": "<entry-uuid>",
  "revision": 1,
  "device_id": "<writer-device-uuid>",
  "created_at": "2026-09-21T12:34:56.789Z",
  "payload": {
    "body": "<UTF-8 正文，<= 1 MiB>",
    "occurred_at": "2026-09-20T08:00:00.000Z",
    "mood": null,
    "tags": [
      {"id": "<tag-uuid>", "name": "旅行", "color": 16711680}
    ],
    "attachments": [
      {
        "id": "<attachment-uuid>",
        "blob_id": "<52-char base32lower>",
        "mime": "image/jpeg",
        "byte_size": 123456,
        "digest": "sha256:<base64url-no-padding>"
      }
    ]
  }
}
```

字段规则：

- `id` 为随机 RFC 4122 UUID v4，是该条目实体的稳定标识，跨 revision 不变。
- `revision` 从 1 开始，每次内容变化 +1，单调递增。
- `created_at` 是对象写入时间，RFC 3339 UTC，精确到 3 位毫秒。
- `payload.body` UTF-8，最大 1 MiB（`DATA_MODEL.md`）。
- `payload.occurred_at` 是事件发生时间，用户可编辑，格式同 `created_at`。
- `payload.mood` 可选；`null` 表示未设置，否则为 1–64 字符 UTF-8。v1 不约定语义枚举，UI 自行映射，新增取值属向后兼容追加。
- `payload.tags` 为数组（可为空），内嵌完整标签对象。
- `payload.attachments` 为数组（可为空），内嵌完整附件元数据。
- `payload` 内所有字段为固定集合，未知字段必须拒绝（`UnsupportedVaultFormatFailure`）。

### 2. Tombstone 对象（kind=tombstone，schema version=1）

```json
{
  "kind": "tombstone",
  "id": "<entry-uuid>",
  "revision": 2,
  "device_id": "<writer-device-uuid>",
  "created_at": "2026-09-21T13:00:00.000Z",
  "payload": {}
}
```

- `id` 等于被删除条目的 `id`；`revision` 严格大于该条目当前 head 的 revision。
- `payload` 固定为空对象；删除是 tombstone，不覆盖、不改写历史对象。
- `DATA_MODEL.md` 的 `Entry.status` 是派生逻辑状态，不写入对象：head 为 `entry` 即 active，head 为 `tombstone` 即 deleted。索引 `entries.status` 据此派生。

### 3. Blob 对象（type=blob，schema version=1）

附件内容是原始字节，明文无 JSON wrapper，直接按 `CRYPTOGRAPHY.md` 以 VMK 加密为 `STOB` envelope。对象 ID 照常为 `base32lower(sha256(envelope bytes))`。附件完整性由 `digest = sha256:<base64url(sha256(明文 blob bytes))>` 表达，与 `blob_id`（密文摘要）正交。

### 4. 标签与附件内嵌于 entry，不新增对象 kind

- 标签与附件元数据的权威表示内嵌于 entry 对象 payload；不引入新的对象 kind，不修改 `OBJECT_FORMAT.md` 的 kind 枚举与 AD。
- manifest `entities` 仍只以 `entry-uuid` 为键跟踪条目，标签/附件随其所属条目对象一起被引用、同步与重建。
- 索引 `tags`/`entry_tags`/`attachments` 表由 entry 对象完整重建；标签的「重复按规范化值禁止」在重建时逐条校验，冲突由应用层呈现。
- `attachment-meta` kind 保留协议位，M2 不启用（预留未来附件元数据独立同步）。
- 代价：重命名标签需更新所有引用该标签的条目（生成新 revision）；v1 接受，属后续优化。

### 5. Manifest 更新事务

对条目实体的每次写（创建/编辑/删除）按固定顺序执行：

1. 生成对象 canonical JSON 明文 → 加密 → 计算 object ID。
2. 原子写 `objects/<aa>/<object-id>`（`aa` 为 ID 前两字符），fsync 目录。
3. 读取当前 HEAD 指向的 manifest，解密并校验。
4. 生成新 manifest：`entities[entry-id].heads` 设为（本地单设备时）`[object-id]`；`parent_ids` 置为 `[旧 manifest_id]`；`created_at`、`writer_device_id` 更新；`known_devices` 合并。其余实体保持不变。
5. 加密新 manifest → 原子写 `manifests/<manifest_id>`，fsync 目录。
6. 原子写新 `HEAD`，fsync 目录。
7. 单事务更新索引（`entries`/`tags`/`entry_tags`/`attachments`）与 `outbox`；`index_meta.manifest_id` 更新为 新 manifest_id。

恢复语义：

- 在第 6 步前中断：HEAD 仍指向旧 manifest，新对象与新 manifest 是孤儿；解锁后保守清理当前 manifest 及祖先链未引用的 `objects/`、非 HEAD `manifests/` 文件（随机 staging 与 `local/` 除外），绝不伪造成功。
- 在第 7 步前中断：HEAD 已指向新 manifest，索引 `index_meta.manifest_id` 与 HEAD 不匹配，由 ADR-0011 的 generation 机制隔离并重建索引。
- 所有持久化写沿用临时文件 → fsync → 原子替换；旧 manifest 与历史对象为 append-only，永不覆盖。

### 6. 加密搜索（search_ciphertext 与 tag 密文列）

- 复用 ADR-0011 的索引 key（`crypto_kdf_derive_from_key(VMK, context="STIDX001", subkey=1, 32 bytes)`）。
- `search_ciphertext` BLOB = `nonce(24) || XChaCha20-Poly1305(body, index_key)`，用于本地快速展示与解锁后搜索。
- `name_ciphertext` = 随机 nonce 加密的标签名称；`normalized_name_ciphertext` = 随机 nonce 加密的规范化名称。两者均为随机 nonce，故数据库 `UNIQUE` 不承担查重语义；标签查重在 application 层解密后比较，避免确定性盲索引泄漏标签频率。
- 搜索与时间线正文展示在解锁后的应用层进行：解密索引中的 `search_ciphertext`/`name_ciphertext` 后在内存匹配，不依赖 SQLite FTS、不拼接用户输入到 SQL。
- 不引入 HMAC 盲索引或确定性加密；`CRYPTOGRAPHY.md` 禁止确定性加密的约束保持成立。

## 安全与兼容性影响

- 新增对象 payload 为 v1 追加，不改变 wrapper、envelope、AD、manifest、HEAD 或 Vault 目录结构；已发布的 v1.0.0 Vault 格式兼容。
- 对象、manifest 时间、设备 ID、正文、标签名、附件元数据均位于密文内，不入日志/遥测。
- `search_ciphertext` 与标签密文列绝不退化为明文；搜索只在解锁后的内存进行。
- 索引永远可由已认证对象重建；对象损坏不因索引而掩盖。

## 验证要求

- entry/tombstone/blob 对象 canonical JSON 固定测试向量；未知 payload 字段、非法 UTF-8、超限 body 硬失败。
- manifest 更新事务的每阶段注入失败：目标 HEAD 保持旧值、孤儿对象可清理、索引 generation 触发重建。
- 从「仅含 entry/tombstone/blob 对象 + manifest」重建索引得到与在线写一致的 entries/tags/entry_tags/attachments。
- `search_ciphertext`、`name_ciphertext`、`normalized_name_ciphertext` 的 nonce 唯一性与加解密往返测试。
- 删除（tombstone）后时间线与索引不返回已删条目，且历史对象仍可恢复。
- 跨平台（Windows/Android/WSL）对固定输入产生逐字节相同的对象与 manifest 密文。

## 备选方案

- 引入独立 `tag`/`attachment` 对象 kind：更独立，但需改 `OBJECT_FORMAT.md` kind 枚举、AD 与 manifest `entities` 语义，扩大协议面，M2 拒绝。
- `normalized_name_ciphertext` 用确定性 HMAC 盲值实现 DB 层 UNIQUE：会引入标签名频率泄漏，且与「禁止确定性加密」精神相悖，拒绝。
- 直接明文存储 `search_ciphertext`：违反 ADR-0011 明文禁令，拒绝。
- `status` 写入 entry payload：与 tombstone 语义重复，且使「删除需写回旧对象」违反不可变性，拒绝。
