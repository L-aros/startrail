# 更新协议

更新清单是签名的 JSON：`channel`、`version`、`published_at`、`min_supported_vault_format`、`artifacts[{platform,url,sha256,size}]`、`notes_url`、`key_id`、`signature`。signature 对 canonical JSON（排除 signature）用离线 Ed25519 发布私钥签名；公钥随应用固定，密钥轮换需要旧密钥签名的新 keyset。

客户端下载前/后验证 HTTPS、签名、平台、版本单调递增、hash 与大小；失败则保留当前版本并显示错误。禁止静默降级、跳过签名、接受仅 HTTP 或自动执行未验证 installer。Android 使用 Google Play/受信分发渠道的签名校验；Windows 安装包需 Authenticode 签名及上述应用层 manifest 校验。格式迁移必须先备份并可回滚应用二进制，除非 ADR 明确不可逆风险。
