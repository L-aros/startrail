# ADR-0017：加密备份容器、隔离验证与导入恢复 v1

- 状态：Accepted
- 日期：2026-09-21
- 决策范围：备份容器格式与密钥层级、隔离验证、导入/恢复事务语义、从已认证对象重建索引

## 背景

Milestone 3 需满足 PRD「带走数据」与 ACCEPTANCE 第 4 项：生成加密 Vault 备份、在另一设备验证并恢复、恢复后 digest 一致、错误密码/篡改/恢复失败不影响原 Vault。现状空白：

1. 尚无备份产物格式；Vault 是「header + objects/ + manifests/ + HEAD + local/index.db」目录，`local/` 为可重建派生索引，不可也不应原样打包。
2. 无「隔离验证」能力：验证一份备份必须不触碰当前 Vault，且错误密码不得改写现有 Vault。
3. 无「导入/恢复」事务：向干净设备恢复需逐文件原子落盘并重建索引，失败必须整体回滚。
4. `vault_session.dart` 的 `populate` 为占位空实现，注释明确「索引从已认证对象重建」落在 M3；`ADR-0011`/`ADR-0016` 已规定重建应产出 `entries/tags/entry_tags/attachments`，但代码尚未实现。

本 ADR 是高风险变更（新格式、新密钥层级、恢复语义），必须 Accepted 后才可编码。

## 提议

### 1. 备份产物：单文件、认证容器，字节级保留权威文件

备份为单文件（建议扩展名 `.stbackup`），包含 Vault 的**权威文件**：`vault.header`、`HEAD`、全部 `objects/<aa>/<object-id>`、全部 `manifests/<manifest-id>`；**不含** `local/`（由索引重建派生）。文件字节与 Vault 内**逐字节一致**，不二次加密：

- 用户数据本已 E2EE（VMK 加密）；容器层只需提供**整体完整性与格式封套**，二次加密不增加机密性，且会破坏「对象密文字节即对象 ID 输入」的可直接校验性质。
- 因此 `object_id = base32lower(SHA-256(envelope bytes))` 在备份、验证、恢复后三处都可直接复核，「digest 一致」自然成立。

容器布局（大端序，流式可增量验证）：

```text
[0..6]   magic "STBKP\0\1" (0x53 54 42 4B 50 00 01)
[7..10]  header_len u32be
[11..]   header   —— 明文 canonical JSON
[..]     manifest_nonce (24 bytes)
[..]     manifest_ciphertext_len u64be
[..]     manifest_ciphertext —— XChaCha20-Poly1305(BK)，含 16B tag
[..]     文件原始字节，按 manifest.files 顺序拼接（长度由 manifest 给出）
```

### 2. 备份 header（明文，格式仿 vault.header）

canonical JSON：

```json
{
  "format": 1,
  "kdf": {"algorithm":"argon2id13","iterations":3,"memory_kib":65536,"parallelism":1,"salt":"<16B b64url>"},
  "vault_uuid": "<vault-uuid>",
  "wrap": {"algorithm":"xchacha20poly1305-ietf","ciphertext":"<48B b64url>","nonce":"<24B b64url>"}
}
```

- `kdf` 参数独立存储；恢复时强制下限（memory_kib >= 65536、iterations >= 3、parallelism == 1），低于下限按 `UnsupportedVaultFormatFailure` 拒绝，防止参数降级攻击。
- `wrap.ciphertext` 为以 KEK 包装的 Backup Key（BK，32B 随机，每次备份新生成）。
- 未知关键字段硬失败；magic 或 `format != 1` 硬失败。

### 3. 密钥层级（复用 CRYPTOGRAPHY.md 原语，无确定性加密）

- KEK = Argon2id(密码, header.salt)，参数见 §2，输出 32B。
- BK 包装：`wrap = nonce(24) || XChaCha20-Poly1305(BK, KEK, AD = "startrail/backup-key/v1" || vault_uuid)`。
- manifest 加密：`ciphertext = XChaCha20-Poly1305(manifest_bytes, BK, nonce(24), AD = "startrail/backup-manifest/v1" || vault_uuid)`。
- 文件完整性由 manifest 逐文件 `digest = sha256:<base64url(sha256(文件字节))>` 表达（与 ADR-0016 附件 digest 同构）。
- 恢复使用**与 Vault 相同的密码**；独立备份密码不在 v1 范围（见备选）。

### 4. backup manifest（BK 加密）

```json
{
  "format": 1,
  "vault_uuid": "<vault-uuid>",
  "created_at": "2026-09-21T12:34:56.789Z",
  "device_id": "<device-uuid>",
  "files": [
    {"path": "vault.header", "size": 123, "digest": "sha256:<b64url>"},
    {"path": "HEAD", "size": 456, "digest": "sha256:<b64url>"},
    {"path": "objects/aa/<object-id>", "size": 789, "digest": "sha256:<b64url>"},
    {"path": "manifests/<manifest-id>", "size": 321, "digest": "sha256:<b64url>"}
  ]
}
```

- `path` 为相对 Vault 根的权威路径；`files` 顺序即容器尾部文件拼接顺序。
- `path` 只允许 `vault.header`、`HEAD`、`objects/<2-char>/<52-char>`、`manifests/<52-char>` 四类，其余拒绝，防路径遍历。
- 未知字段硬失败；`vault_uuid` 必须与 header 一致。

### 5. 隔离验证（BackupVerifier，只读）

输入备份文件 + 密码，输出结构化报告，**永不写当前 Vault**：

1. 读 magic/版本 → 读 header → 校验 KDF 下限 → 派生 KEK → 解包 BK（认证失败 = `wrong_password`）。
2. 解密 manifest（认证失败 = `tampered`）。
3. 流式读文件区，按 `files` 尺寸切分，逐文件 SHA-256 与 manifest 比对；对 object 额外校验 `object_id == base32lower(SHA-256(bytes))` 且与路径一致（不一致 = `tampered`）。
4. 校验 `HEAD` 的 `manifest_id`/`manifest_cipher_digest` 指向一份真实存在于备份、且 digest 匹配的 manifest。
5. 报告：`{status: ok|wrong_password|tampered|corrupt|unsupported, vault_uuid, file_count, object_count, total_bytes, root_digest}`。`root_digest` 为 manifest 密文的 `sha256:<b64url>`，供跨设备比对备份副本。

验证全程仅用内存与可丢弃临时流，不触碰现有 Vault 目录。

### 6. 导入/恢复（BackupRestorer，事务化）

1. **先完整隔离验证**（§5）；非 `ok` 直接中止，目标目录零改动。此步满足「错误密码/篡改/恢复失败不影响原 Vault」。
2. **暂存提取**：在目标目录**之外**（同卷优先，保证原子 rename）的独立临时目录内，逐文件走「临时文件 → fsync → 原子替换」落盘。
3. **复验暂存文件**（digest 与 object_id），再**原子交换**：目标不存在 → rename 暂存目录为目标（含目录 fsync）；目标已存在且非空 → 默认拒绝，需用户显式确认替换。
4. **重建索引**：以 §7 的 `populate` 重建 `entries/tags/entry_tags/attachments`，再打开会话。
5. 任一步失败 → 丢弃暂存目录，目标保持不变；绝不以半成品覆盖。

### 7. 索引重建（IndexPopulator，落地 ADR-0011/0016）

实现 `vault_session.dart` 的 `populate` 占位：给定解锁后的 Vault（VMK、vault_uuid、manifest 明文、objects/ 目录），从当前 manifest 的 `entities[id].heads` 出发（manifest 为全量快照，见 ADR-0016），解密每个 head 对象：

- `entry` → 写 `entries`、`tags`、`entry_tags`、`attachments`，`search_ciphertext`/标签密文列按 ADR-0016 §6 生成。
- `tombstone` → 派生 `status=deleted`，不返回于时间线。
- 标签按规范化值去重，冲突交由应用层呈现（ADR-0016 §4）。
- 任一对象认证失败 → 硬失败，绝不伪造成功。

这是既有 ADR 的落地，不新增协议面；`VaultSession.open` 需把 `populate` 闭包改为持有 `unlocked`（VMK/vault_uuid/manifest 明文）+ vault 目录 + sodium 的实现（内部接线重构，不改格式）。

## 安全与兼容性影响

- 新产物为**独立格式**，不改 Vault 目录结构、对象编码、manifest/HEAD 语义或已发布 `vault_format_version`；v1.0.0 Vault 完全兼容。
- 容器层不二次加密，用户内容机密性仍由 VMK 保证；容器泄露面仅限 `vault_uuid`、KDF 参数、文件数量与大小，与威胁模型已接受的「可见大小/频率」一致。
- BK/KEK/明文 buffer 用完即清零；随机数取 OS CSPRNG，杜绝 nonce 重用。
- 备份 header 的 KDF 参数可被攻击者改小以加速离线爆破——以「恢复强制下限」缓解；Vault 侧已有等价规则。
- 密码、VMK、BK、明文不入日志/遥测；备份路径与对象 ID 视为敏感。

## 验证要求

- 固定测试向量：header、BK 包装、manifest 加解密与 AD 绑定；篡改任一文件字节/替换 object/改 magic/降 KDF 参数均硬失败。
- 隔离验证对「正确密码/错误密码/篡改/截断/未知格式」给出确定 `status`，且全程不产生对现有 Vault 的任何写入。
- 备份→恢复→重建索引 与在线写得到逐字节一致的 `entries/tags/entry_tags/attachments`；object_id 在恢复后仍等于 `base32lower(SHA-256(bytes))`。
- 注入失败（暂存写中断、交换前中断、索引重建失败）后目标目录保持不变，原 Vault 可正常打开。
- 100 对象 + 附件往返压测；跨平台（Windows/Android/WSL）对同一 Vault 产出逐字节一致的备份容器。

## 备选方案

- **目录级原样拷贝**：实现最简单，但不构成单文件产物，无法在另一设备便携验证，且会把 `local/` 派生索引一并带走，拒绝。
- **容器整体二次加密**：更强地隐藏文件数量/大小，但需双倍 CPU/空间，破坏「对象字节即 ID」的即时校验，且威胁模型已接受大小/频率可见，拒绝。
- **独立备份密码**：允许备份用不同于 Vault 的密码，用户体验更灵活，但引入第二密钥材料与遗忘风险；v1 保持同密码，保留将来对 BK 重包装的扩展位。
- **恢复时合并已有 Vault**：多设备导入合并语义复杂、涉及冲突与实体 ID 碰撞；v1 恢复仅支持干净目标或经显式确认的替换，合并留给同步里程碑（M4）后评估。
