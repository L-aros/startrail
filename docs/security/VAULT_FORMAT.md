# Vault 格式 v1

```text
vault/
  vault.header                 # 未加密：魔数、版本、KDF 参数、salt、wrapped VMK
  objects/aa/<object-id>       # 密文、不可变
  manifests/<manifest-id>      # 密文、不可变
  HEAD                         # 仅含当前 manifest-id、版本、校验；不含语义
  local/index.db               # 加密派生索引，不同步
```

`vault.header` 有魔数 `STVLT\0\1`、`vault_format_version`、vault UUID、Argon2id 参数、16-byte salt 和以 KEK 包装的 32-byte Vault Master Key (VMK)。header 认证失败或未知关键字段必须拒绝打开。对象 ID 是 `base32(lowercase, SHA-256(ciphertext bytes))`，长度 52；目录前缀是前两个字符。

`HEAD` 可以公开存在但没有条目名称、计数或日期；其内容为 canonical JSON `{format:1,manifest_id,manifest_cipher_digest}`。更新的原子性来自本地原子替换或远端 ETag 条件 PUT。格式版本按语义兼容规则演进，详见 ADR policy。
