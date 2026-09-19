# Cloudflare R2 同步协议 v1

R2 是不可信 blob 存储。用户提供限定 bucket/prefix 的 S3 兼容 endpoint、access key、secret（存于平台安全存储）；建议权限仅 `ListBucket/GetObject/PutObject`，禁止 DeleteObject。远端前缀：`startrail/v1/<vault-uuid>/`，其下镜像 `objects/`、`manifests/`、`HEAD`。

## 同步流程

1. 解锁 Vault，读取本地 HEAD，拉取远端 HEAD（不存在视为初始）。
2. 下载并认证双方 manifest；从共同祖先合并实体 heads，保留所有并发版本。
3. 先上传所有缺失不可变对象和新 manifest；每个上传校验 SHA-256 密文 digest 与 ETag/下载抽检。
4. 对远端 HEAD 执行 If-Match ETag 条件 PUT。若 412，重新拉取、合并、上传新 manifest、重试，最多 5 次指数退避。
5. HEAD 成功后写本地 HEAD/索引，标记 outbox 已提交。

上传可幂等：同 object-id 的字节必须完全相同，否则视为仓库损坏并停止。禁止“最后写入获胜”的无提示覆盖。每次同步可取消；取消只留下可达但未引用的不可变对象，后续可安全重试。

## 凭据与网络

TLS 证书错误硬失败；不回退 HTTP。不得记录 Authorization、endpoint、签名请求或对象 ID。显示存储提供商的数据保留与网络元数据风险，R2 配置可一键移除本机安全存储。
