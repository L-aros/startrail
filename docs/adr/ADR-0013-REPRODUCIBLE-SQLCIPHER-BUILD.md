# ADR-0013：可复现 SQLCipher 源码构建与 raw-key 符号导出

- 状态：Proposed
- 日期：2026-09-20
- 决策范围：关键数据库依赖、原生构建供应链、Android/Windows/Linux 兼容性

## 背景

ADR-0012 已接受通过 `sqlite3_key_v2` 传递 32-byte raw key，以避免把密钥复制到不可清零的 Dart String。实施探针发现 sqlite3 Dart package 3.3.4 的 `source: sqlcipher` 并不编译源码，而是下载其 GitHub release 中的预编译动态库。当前 Linux x64 产物 SHA-256 为 `46205b329223ece8fd545bed40dd68f03d2c5cec5bab5487407fc28aa66a0b63`，包含 SQLCipher，但动态符号表没有 `sqlite3_key_v2` 或 `sqlite3_rekey_v2`。

仅给 Dart FFI 增加声明会在运行时得到 undefined symbol；`PRAGMA key = ?` 又不接受参数绑定。继续实施因此需要改变 SQLCipher 原生库的构建与分发方式，属于关键依赖及供应链变更。

## 提议

### 固定输入

- vendoring sqlite3 Dart package `3.3.4` 的精确发布源码，并应用 ADR-0012 的最小绑定补丁；版本标记为 `3.3.4+startrail.1`。
- vendoring 与该 package 发布构建相同的 SQLCipher community 源码快照；在首次实现提交前将 upstream tag、commit、源码归档 SHA-256、生成 amalgamation 的命令和编译器版本写入 `third_party/sqlite3/PATCHES.md` 与 `THIRD_PARTY.md`。
- 固定 SQLite/SQLCipher compile defines、OpenSSL ABI、目标三元组与 release flags；任何输入变化都视为依赖升级，需独立 diff、测试和 ADR 复核。
- 上游 LICENSE、NOTICE、源码 hash、patch 和构建清单均进入仓库；生成的二进制不得作为唯一可重建来源。

若无法从 sqlite3 3.3.4 的发布构建记录证明 SQLCipher 精确源码输入，则停止实施并另提版本选择 ADR，不用“最新版本”替代。

### 构建与导出

- 使用 sqlite3 package 的 native-assets source build 路径构建 SQLCipher，不再使用 `source: sqlcipher` 的预编译下载路径。
- 只额外导出 `sqlite3_key_v2`；暂不导出 rekey API。既有 sqlite3 所需符号白名单保持不变。
- 开启 SQLCipher codec、memory security 与项目已固定的 SQLite 安全选项；链接受支持的 OpenSSL，不允许运行时回退普通 SQLite。
- Android API 29+、Windows x64、WSL/Linux x64 使用同一份锁定源码、defines 和补丁；平台差异只允许出现在工具链、OpenSSL library path 和必要链接 flags，并记录在构建清单。
- 构建输出记录 SHA-256 和可审计 SBOM；CI 从干净缓存重建并比较输入清单。若二进制无法逐字节复现，至少必须证明源码、defines、导出符号和依赖 ABI 一致，并记录非确定性来源。

### 失败策略与回滚

- 启动数据库前检查 `sqlite3_key_v2` 存在；缺失即硬失败，不执行任何 Schema SQL。
- 设 key 后验证 `cipher_version` 非空，并执行 ADR-0011 的完整性门禁；普通 SQLite、错误 OpenSSL ABI 或错误 key 均不得创建/替换正式索引。
- 新库先只用于派生 `index.db`；失败可删除或隔离并从已认证 manifest 重建，不修改 Vault 权威对象。
- 回滚到旧预编译库只允许停用索引功能；禁止回滚到 String/hex PRAGMA。

## 安全、隐私与兼容性影响

- 不改变 Vault、对象、manifest、HEAD、数据库 Schema 或同步协议。
- 增加维护 SQLCipher/OpenSSL 原生构建的供应链责任，也消除 key 进入 Dart String、SQL 文本、trace 或异常的路径。
- 构建日志只能包含版本、hash、defines 和符号名；不得包含 key、Vault 路径、对象名或 fixture 正文。
- 只上传/发布由锁定输入产生并通过 hash、符号及加密行为门禁的产物。

## 验证要求

- Android、Windows、WSL/Linux 的动态符号测试证明 `sqlite3_key_v2` 可调用，普通 SQLite fixture 硬失败。
- 固定非秘密 key 创建数据库，关闭后同 key 重开成功，错误 key 返回 `SQLITE_NOTADB` 或等价鉴权失败。
- instrumentation 证明 native 临时 key buffer 在成功、SQLCipher 错误和符号错误路径均被覆盖后释放。
- `cipher_version`、compile options、OpenSSL ABI 与锁定清单一致；缺失 codec 的构建失败。
- 数据库、WAL、SHM、日志及测试报告扫描不含 key bytes、hex key 或 fixture 正文明文。
- 干净缓存完成源码获取校验、patch 重放、三平台构建、许可证/SBOM 和上游 diff 门禁。

## 迁移

尚无已发布 index 数据，无用户数据迁移。首次采用后沿用 ADR-0011 Schema v1；未来 SQLCipher/OpenSSL 升级必须先证明旧索引可读，或安全隔离后从权威对象重建。

## 备选方案

- 继续使用预编译库并只补 Dart binding：目标符号不可解析，拒绝。
- 使用 `PRAGMA key` 拼接 hex/String：不可清零并扩大泄露面，违反 ADR-0012，拒绝。
- 使用系统 SQLCipher：版本、defines、导出和 OpenSSL ABI 不可控，跨平台不可复现，拒绝。
- 提交无法追溯源码的自建二进制：供应链不可审计，拒绝。
