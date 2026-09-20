# ADR-0012：sqlite3 raw-key 原生绑定补丁

- 状态：Accepted
- 日期：2026-09-20
- 决策范围：关键数据库依赖、密钥内存生命周期、原生 FFI

## 背景

ADR-0011 要求 SQLCipher 使用 32-byte raw key，且临时 key 表示可显式清零。锁定的 sqlite3 3.3.4 只公开 SQL 执行接口；其官方加密测试使用字符串插值：

```sql
PRAGMA key = '...'
```

实测 `PRAGMA key = ?` BLOB 参数绑定在 SQLCipher 上返回 `near "?": syntax error`。将 SecureKey 转为 hex/passphrase Dart `String` 会产生不可显式清零、生命周期由 GC 控制的密钥副本，违反 AGENTS.md 与 ADR-0005/0011。

SQLCipher 原生 API 提供 `sqlite3_key_v2(sqlite3*, "main", key_ptr, key_len)`，可直接接收 SecureKey 解锁回调中的 bytes，不需要 Dart String。

## 提议

在仓库 `third_party/sqlite3/` vendoring sqlite3 Dart package 3.3.4 的精确源码，并维护一个最小补丁：

1. 原生 FFI binding 增加 SQLCipher `sqlite3_key_v2` 符号；
2. 仅 FFI database implementation 暴露 `applyRawKey(Uint8List key)`；
3. 调用时在 native arena 分配精确长度 buffer、复制 SecureKey callback view、调用 `sqlite3_key_v2`，并在 `finally` 中用显式逐字节覆盖后释放；
4. 不增加 passphrase/String API，不启用 SQL trace，不把 key 放入异常；
5. 非 SQLCipher 构建缺少符号或返回非 `SQLITE_OK` 时硬失败；
6. infrastructure 仅通过一个窄 `SqlCipherRawKeyAdapter` 使用 vendored API，其余数据库代码不依赖 package `src/` 内部类型。

根 `pubspec` 路径依赖指向 vendored package，并保留版本 `3.3.4+startrail.1`。必须保存：

- 上游 tag/commit 与源码归档 SHA-256；
- `PATCHES.md` 中逐文件补丁说明；
- 上游 MIT LICENSE；
- 可机械重放的 patch；
- 与上游 3.3.4 的 diff 门禁，禁止夹带无关修改。

## 为什么不采用 String PRAGMA

- Dart String 不可原地清零；
- SQL 文本、异常、调试器和潜在 trace 扩大密钥暴露面；
- 即使源 `Uint8List` 被清零，hex/passphrase String 仍可能留在托管堆；
- 这与“密钥只存在内存中的受控安全材料、用完清零/释放”直接冲突。

## 安全与兼容性影响

- 增加关键依赖维护责任，但不改变数据库文件格式、Schema、Vault 协议或网络行为。
- 实施探针确认 sqlite3 3.3.4 下载的预编译 SQLCipher 隐藏 `sqlite3_key_v2`；因此本 ADR 的绑定补丁必须在 ADR-0013 解决可复现原生库构建后实施，禁止回退到 String PRAGMA。
- raw key 与 ADR-0011 的 SQLCipher 数据库兼容；从 String PRAGMA 改为 `sqlite3_key_v2` 不改变派生 key bytes。
- vendored package 只能构建 SQLCipher source；普通 SQLite 构建必须在 raw-key 初始化阶段失败。
- 所有平台需要验证符号可用性；Android API 29+、Windows x64、WSL Linux 必须运行同一错误 key 与明文扫描测试。

## 验证要求

- 测试证明 `PRAGMA key = ?` 不可用，防止未来误回退（测试不得包含真实 key）。
- 固定非秘密 key 创建数据库，关闭后以同 key 重开成功，错误 key 返回 `SQLITE_NOTADB`。
- 数据库、WAL、SHM 不包含 key bytes、hex key 或 fixture 正文明文。
- instrumented adapter 证明 native 临时 buffer 在成功和异常路径均被覆盖后释放。
- `cipher_version` 必须非空；链接普通 SQLite fixture 时 hard fail。
- vendored diff、许可证、源码 hash 和 SBOM 门禁通过。

## 备选方案

- PRAGMA 字符串插值：无法清零 Dart String，拒绝。
- 修改 sqlite3 package cache：不可复现且不会进入版本控制，拒绝。
- 使用 package 私有 FFI 类型取得句柄：依赖未承诺的 `src/` ABI，升级脆弱且仍缺少 key symbol，拒绝。
- 更换数据库封装/SQLCipher SDK：扩大关键依赖和平台迁移范围，当前不选。
