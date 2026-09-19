# 数据模型

所有 UUID 为随机 UUIDv4；时间使用 RFC 3339 UTC，展示时按设备时区。`revision` 是单调递增逻辑版本；`device_id` 是每 Vault 每设备随机 ID，不能作跨 Vault 追踪。

| 实体 | 必填字段 | 说明 |
|---|---|---|
| Entry | id, revision, created_at, updated_at, occurred_at, body, status | 正文记录；status: active/deleted |
| Attachment | id, entry_id, blob_id, mime, byte_size, digest | blob 是不可变密文对象 |
| Tag | id, name, color | name 在本地加密索引；重复按规范化值禁止 |
| Device | device_id, display_name, first_seen_at | 加密 manifest 内的协作元数据 |
| Conflict | entity_id, sibling_revisions, detected_at, resolution | 本地工作队列，可重建 |

Entry 的可同步 canonical JSON 使用 UTF-8、键名排序、无多余空白、RFC 8785 JCS 规范化；`body` 最大 1 MiB，单附件默认最大 250 MiB（可由设置降低）。删除是 tombstone，保留至少 90 天且所有已知设备确认后才可 GC。
