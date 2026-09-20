# ADR-0009：Vault Header v1 二进制编码

- 状态：Proposed
- 日期：2026-09-20
- 决策范围：已发布 Vault 格式、密码学元数据编码

## 背景

现有规范要求 `vault.header` 包含 `STVLT\0\1` 魔数、格式版本、Vault UUID、Argon2id 参数、16-byte salt，以及以 KEK 包装的 32-byte VMK，但没有规定字段顺序、长度、整数端序、二进制字段文本编码或未知字段策略。若各平台自行决定，Vault 将无法互操作，也无法建立稳定测试向量。

## 提议

`vault.header` v1 使用以下结构：

```text
magic       7 bytes   53 54 56 4c 54 00 01（STVLT\0\1）
json_length u32be     canonical JSON payload 的字节数
payload     N bytes   UTF-8 canonical JSON，不带 BOM/换行
```

payload 固定字段：

```json
{
  "format":1,
  "kdf":{
    "algorithm":"argon2id13",
    "iterations":3,
    "memory_kib":65536,
    "parallelism":1,
    "salt":"base64url-no-padding"
  },
  "vault_uuid":"lowercase UUID with hyphens",
  "wrap":{
    "algorithm":"xchacha20poly1305-ietf",
    "ciphertext":"base64url-no-padding",
    "nonce":"base64url-no-padding"
  }
}
```

- v1 读取器要求字段集合完全匹配；缺失字段、重复 JSON key、未知关键字段、尾随字节、非 canonical JSON、非法 UTF-8 或错误长度均拒绝打开。
- salt 必须解码为 16 bytes，nonce 为 24 bytes，wrapped ciphertext 为 48 bytes（32-byte VMK + 16-byte tag）。
- KDF 参数不得低于 v1 基线；v1 写入器只能写入上述固定参数。
- VMK 包装 AD 保持既有规范：UTF-8 `startrail/vault-header/v1` 紧接 16-byte UUID 原始值。
- UUID 文本仅用于 header 表示；构造 AD 时解析为 RFC 4122 网络字节序的 16 bytes。
- 密码或 header 认证失败均只向上层返回 `VAULT_AUTH_FAILED`，不得暴露失败字段。

## 理由

短二进制前导可在解析 JSON 前限制长度并快速拒绝错误文件；canonical JSON 便于跨 Dart/平台生成测试向量和人工诊断。base64url 无填充避免多种等价文本编码。严格字段集合防止旧实现忽略未来安全关键字段后写回造成数据损坏。

## 安全与兼容性影响

- 这是 Vault 线格式决策；一经 Accepted 并发布，只能追加兼容。
- header 中 UUID、KDF 参数和随机材料不视为内容明文，但仍不得记录到日志或遥测。
- KDF 参数在解包前必须可读，因此篡改主要造成拒绝服务；VMK ciphertext 的 AEAD 认证阻止攻击者构造可成功解包的降级 header。
- 解析器必须先施加文件大小上限，再分配 payload。

## 验证要求

- 固定 canonical header 测试向量及逐字节期望值。
- 错误密码、修改 UUID/KDF/nonce/ciphertext、未知字段、重复 key、截断、尾随数据与超限长度全部硬失败。
- Android、Windows、WSL 对同一 fixture 产生相同 bytes。

## 备选方案

- 全固定宽度二进制：更紧凑，但扩展与人工检查困难。
- CBOR：需要新增关键依赖及 canonical CBOR 约束，当前收益不足。
- 纯 JSON 无前导：无法在完整解析前可靠限定声明长度与识别格式。
