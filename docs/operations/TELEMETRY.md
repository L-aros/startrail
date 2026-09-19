# Telemetry

默认关闭、明确 opt-in、可随时停止。仅允许计数/桶化事件：`app_open`、`vault_create_result`、`sync_result`（result/error_code/duration_bucket/object_count_bucket）、`update_result`。不带用户、Vault、设备稳定标识；使用每次安装随机且可重置的 telemetry ID，且不得与 R2 请求关联。

遥测端点、保留期、处理者和法律文本在启用界面公布并经 ADR 批准。若无法保证上述字段过滤，宁可不实现遥测。
