# 加密规范 v1

此规范是互操作契约；实现必须使用经过审计的库并增加已知答案测试。

1. 用户密码经 **Argon2id** 派生 32-byte KEK：salt 16 bytes，memory 64 MiB，iterations 3，parallelism 1，输出 32 bytes。参数存在 header，最低版本不得下调。
2. 新 Vault 产生 32-byte 随机 VMK。用 XChaCha20-Poly1305 包装 VMK；nonce 24 bytes 随机，AD 是 `startrail/vault-header/v1 || vault_uuid`。
3. 每个对象产生 24-byte 随机 nonce，使用 XChaCha20-Poly1305 和 VMK；AD 是 `startrail/object/v1 || vault_uuid || object_type || plaintext_schema_version`。
4. 密文 envelope：`STOB` (4) | version u8 | type u8 | schema u16be | nonce 24 | ciphertext+tag。认证失败即硬失败。
5. 密码、VMK、KEK 与明文 buffer 用完即清零/释放；平台安全存储仅可保存经设备密钥包装的 VMK，绝不保存用户密码。

随机数必须来自 OS CSPRNG。禁止 AES-ECB/CBC、自定义加密、nonce 重用、确定性加密、压缩后未限制解压大小。密码变更仅重包 VMK；数据重钥须创建新 VMK 并全量迁移，必须 ADR。
