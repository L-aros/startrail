# ADR-0005：Milestone 1 密码学与加密索引依赖

状态：**Proposed**；日期：2026-09-20。

## 背景

Milestone 1 需实现 CRYPTOGRAPHY.md 已冻结的 Argon2id（64 MiB、3 轮、并行度 1）、XChaCha20-Poly1305、OS CSPRNG、敏感密钥内存生命周期，以及 Android/Windows 可用的加密 SQLite 派生索引。这些选型位于安全边界且会引入关键原生依赖，必须在编码前批准。

## 拟议决策

1. 锁定 Flutter 3.41.6 / Dart 3.11.4 作为首个可重现开发基线，升级须单独审查 lockfile、平台构建和回归测试。
2. 采用 sodium 4.1.0+1（BSD-3-Clause/ISC）作为密码 adapter，并由其 build hook 构建 libsodium 1.0.22。仅调用 Argon2id v1.3、XChaCha20-Poly1305-IETF、OS CSPRNG 与受保护的 SecureKey；密钥必须显式 dispose，KDF 在工作 isolate 执行。
3. 采用 sqlite3 3.6.0（MIT）的 build hook，明确选择 source: sqlcipher（SQLCipher Community + OpenSSL）。打开后必须先验证 PRAGMA cipher_version，为空即拒绝创建/打开，防止静默退化为明文 SQLite。SQL 全部参数化。
4. 不在 vault.header 增加未规定字段。索引密钥从 VMK 通过 libsodium crypto_kdf_derive_from_key 派生：8-byte ASCII context STIDX001，subkey_id = 1，输出 32 bytes。该密钥只在打开索引时存活，关闭 Vault 后释放。
5. SQLite 只是可重建派生数据；任何 cipher/完整性/index_generation 失败都隔离旧库并从已认证对象重建，不改写权威对象。
6. 本 ADR 不改变 Vault v1、STOB envelope、AD、manifest 或 HEAD 字节语义。固定测试向量以 libsodium 与独立实现交叉验证。

## 备选

- cryptography 2.9.0：API 简洁并纯 Dart 跨平台，但密钥存在 GC 管理内存，对“用完清零/释放”的可验证性弱于 libsodium SecureKey。
- SQLite3MultipleCiphers：与 sqlite3 集成方式相同，但本项目优先选择文档、交叉平台经验和加密格式更成熟的 SQLCipher。
- 整库文件自定义加密：需自建 VFS/页缓存并扩大崩溃一致性攻击面，拒绝。
- 索引随机密钥包装后写入 header：会改变已定义的 Vault header 语义，拒绝。

## 后果

收益是密码原语来自成熟原生库、密钥可显式释放，且两个目标平台使用同一代码路径。代价是增加原生构建与供应链复杂度；Windows 上交叉构建 Android 需可用的 Git Bash 和 make，SQLCipher 还引入 OpenSSL。构建产物必须保存 lockfile、hash/provenance 和 SBOM，不允许运行时下载代码。

## 迁移与回滚

当前尚无已发布 Vault，因此无数据迁移。引入后若任一目标平台的固定向量、性能基准或构建来源验证失败，在首次发布前回滚依赖并重新提交 ADR；不保留不完整的兼容路径。发布后的密码学、KDF context 或 SQLite cipher 变更必须以新 ADR 和显式迁移处理。

## 测试

- Argon2id 已知答案，参数下调拒绝，错误密码统一错误。
- XChaCha20-Poly1305 已知答案、AD 字节精确性、nonce 长度/唯一性、任意密文位翻转硬失败。
- SQLCipher 静态密文扫描、错误密钥、普通 SQLite 静默退化防护、从对象重建。
- Android 10+ 与 Windows 10/11 x64 的同一 fixture 交叉打开；断电点、磁盘满和锁定后密钥释放。
- 两个依赖的 SBOM、许可证与已知漏洞扫描纳入 CI。

## 安全/隐私影响

不新增网络行为、遥测或远端数据流。build hook 只在依赖解析/构建期获取或构建固定原生源码；发布构建必须验证来源和 hash。日志不得包含密钥、密码、Vault 路径、对象 ID、SQL 或原始异常。
