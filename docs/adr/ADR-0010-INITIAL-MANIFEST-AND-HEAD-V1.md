# ADR-0010：初始 Manifest 与 HEAD v1 编码

- 状态：Accepted
- 日期：2026-09-20
- 决策范围：Manifest/HEAD 已发布格式与本地路径

## 背景

现有规范要求创建 Vault 时写入初始空 manifest 与 HEAD，并规定对象 ID 为密文字节 SHA-256 的 lowercase base32，但没有明确：

- `manifest_cipher_digest` 的文本编码和算法标识；
- manifest 文件是否使用对象分片目录；
- 初始 manifest 的时间精度、设备标识和 `known_devices` 内容；
- HEAD 是否允许未知字段、非 canonical JSON 或尾随数据。

这些差异会导致不同平台生成互不兼容的 Vault，并可能让旧读取器忽略未来安全关键字段。

## 提议

### Manifest 密文与标识

- 初始 manifest 明文直接使用 `OBJECT_FORMAT.md` 的 Manifest v1 JSON，不再套通用实体 wrapper。
- 使用 object type `manifest`、plaintext schema version `1` 和既有对象 AD 加密为 `STOB` envelope。
- `manifest_id` 为 `base32lower(sha256(envelope bytes))`，无填充、固定 52 字符。
- manifest 存储路径固定为 `manifests/<manifest_id>`，不采用 `objects/aa/` 分片。
- `manifest_cipher_digest` 固定为 `sha256:<base64url-no-padding digest>`；冒号后为同一 32-byte SHA-256 digest 的 43 字符编码。
- 读取 HEAD 时必须分别解码 ID 与 digest，验证二者表示同一 digest，并重新计算 manifest 密文字节摘要。

### 初始 Manifest

创建 Vault 时生成随机 lowercase RFC 4122 UUID v4 作为 `writer_device_id`。初始 manifest 为：

```json
{
  "created_at":"RFC3339 UTC with exactly 3 fractional digits",
  "entities":{},
  "format":1,
  "known_devices":{"<device-uuid>":{"last_seen_at":"same timestamp"}},
  "parent_ids":[],
  "writer_device_id":"<device-uuid>"
}
```

时间示例：`2026-09-20T12:34:56.789Z`。同一创建事务内两个时间字段必须逐字节相同。

### HEAD

HEAD 是无 BOM、无换行的 UTF-8 canonical JSON：

```json
{"format":1,"manifest_cipher_digest":"sha256:<digest>","manifest_id":"<id>"}
```

- v1 字段集合必须完全匹配；未知/缺失/重复字段、非法 UTF-8、非 canonical JSON、尾随空白均拒绝。
- `format != 1` 返回不支持格式；摘要、ID、长度或 manifest 内容不匹配返回数据损坏。
- HEAD 不包含时间、设备、实体计数或其他语义。

## 创建事务顺序

1. 在目标同级创建随机 staging 目录。
2. 写入并同步 `vault.header`、初始 manifest 和 HEAD；创建并同步 `objects/`、`manifests/`、`local/`。
3. 验证 staging 内 header、HEAD、manifest 可完整读取和认证。
4. 原子重命名 staging 为目标目录并同步父目录。
5. 任一步失败都删除未发布 staging；目标路径不得出现半成品 Vault。

## 安全与兼容性影响

- manifest 与 HEAD 字节语义一经 Accepted 并发布只能追加兼容。
- HEAD 的两种摘要编码是同一值的交叉表示，可检测编码/路径错误，但不替代 AEAD 与 manifest 父链验证。
- manifest 时间与设备 ID 位于密文内，不得记录到日志或遥测。
- staging 清理只允许作用于本次创建且经随机名称与父目录校验的路径。

## 验证要求

- SHA-256、base32lower、digest 文本与 HEAD 固定测试向量。
- 初始 manifest canonical JSON 固定测试向量。
- 修改 ID、digest、manifest 密文、字段集合或 canonical 表示均硬失败。
- 在 header、manifest、HEAD、最终 rename 各阶段注入失败，目标路径不存在且 staging 被清理。
- Android、Windows、WSL 对固定输入产生相同 manifest 与 HEAD bytes。

## 备选方案

- digest 直接复用 `manifest_id`：字段冗余且无法发现编码路径错误。
- lowercase hex digest：可读但比 base64url 多 21 字符。
- manifest 使用 `objects/aa/` 分片：与当前 Vault 目录规范不一致，且 manifest 数量通常远小于内容对象。
