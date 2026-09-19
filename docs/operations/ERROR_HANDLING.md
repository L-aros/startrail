# 错误处理

错误类型是可判定、可操作的 domain result，不以异常文本驱动 UI。对用户显示简洁动作，对本地诊断记录脱敏错误码与因果链。

| 代码 | 行为 | 用户动作 |
|---|---|---|
| `VAULT_AUTH_FAILED` | 不打开/不写入 | 检查密码或恢复副本 |
| `OBJECT_TAMPERED` | 隔离对象、停止相关同步 | 用已验证备份恢复/报告 |
| `STORAGE_UNAVAILABLE` | 保留 outbox | 重试/离线继续 |
| `SYNC_CONFLICT` | 保留 siblings | 打开冲突解决器 |
| `HEAD_RACE_EXHAUSTED` | 不更新远端 HEAD | 稍后同步 |
| `DISK_FULL` | 中止原子写前提交 | 释放空间后重试 |
| `UNSUPPORTED_FORMAT` | 只读/拒绝写回 | 更新应用或导出 |

永不在错误 UI/日志显示密码、明文内容、URL query、authorization、完整路径或对象 ID。所有可重试操作有上限、取消和幂等性。
