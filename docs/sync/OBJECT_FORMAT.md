# 对象格式与 Manifest

对象明文封装前是 canonical JSON：`{kind,id,revision,device_id,created_at,payload}`。`kind` 为 `entry`、`tombstone`、`attachment-meta` 或 `manifest`；媒体 blob 的明文为原始 bytes，type 为 `blob`。所有对象按 `CRYPTOGRAPHY.md` 加密；对象 ID 由密文字节得出，故不会泄漏内容相同与否。

## Manifest v1

manifest 是加密的 canonical JSON：

```json
{"format":1,"parent_ids":["…"],"created_at":"2026-01-01T00:00:00Z","writer_device_id":"…","entities":{"entry-uuid":{"heads":["object-id"]}},"known_devices":{"device-id":{"last_seen_at":"…"}}}
```

`heads` 是同一实体的一个或多个并发对象头；正常单值，冲突时多值。manifest 不内嵌对象内容。父 manifest 可为 0（初始）、1（线性）或 >1（合并）。对象不可修改；未知 `format/kind` 保留且阻止写回会丢失的数据。
