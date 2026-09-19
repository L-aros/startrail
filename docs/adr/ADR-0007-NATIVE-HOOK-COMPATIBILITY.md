# ADR-0007：Sodium 与 SQLCipher 构建钩子兼容基线

状态：**Accepted**；日期：2026-09-20。

## 背景

ADR-0005 锁定 sqlite3 3.6.0，ADR-0006 锁定 sodium 4.0.2+1。实际 Pub 求解显示 sqlite3 3.6.0 依赖 hooks ^2.2.0，而 sodium 4.0.2+1 依赖 hooks ^1.0.2，两者互斥。禁止使用 dependency_overrides 强制拼接不同主版本的原生构建协议。

兼容性探针确认 sodium 4.0.2+1 与 sqlite3 3.3.4 可共同解析到 hooks 1.0.3。sqlite3 3.3.3 已恢复 SQLCipher 支持，3.3.4 在其上修复原生资产重复下载问题。

## 拟议决策

将 sqlite3 精确锁定为 3.3.4，sodium 继续精确锁定为 4.0.2+1，共享 hooks 1.0.3。继续使用 sqlite3 build hook 的 source: sqlcipher，并保留 ADR-0005 的 cipher_version 硬检查、数据库密钥派生、测试和回滚要求。

不得使用 dependency_overrides；不得静默改用普通 SQLite、SQLite3MultipleCiphers 或系统 SQLite。升级任一 native-assets 依赖时，必须先证明共同的 hooks/code_assets/native_toolchain_c 依赖可解析，并重新运行 Android/Windows 构建和密码学/静态加密测试。

## 备选

- 保留 sqlite3 3.6.0 并强制 hooks 2.x：sodium 的构建钩子未声明兼容，拒绝。
- 升级 sodium 到兼容 hooks 2.x 的版本：要求当前工具链不具备的 Dart 3.12/3.13，拒绝。
- 使用 sqlite3 2.x + sqlcipher_flutter_libs：后者已 EOL，且回退旧 Flutter 专用装载路径，拒绝。

## 后果

失去 sqlite3 3.5.2+ 提供的 SLSA level 3 原生二进制证明和后续修复，因此必须固定下载 hash、记录生成 SBOM，并主动审计 3.3.4 至 3.6.0 的安全修复差异。收益是无需覆盖依赖约束即可得到一致、可复现的原生构建图。

## 迁移/回滚

尚无已发布应用或 Vault，无数据迁移。若 SQLCipher Windows/Android 构建、cipher_version 或静态加密验证失败，删除依赖和构建产物，重新提出 ADR。

## 测试

- Pub lockfile 精确包含 sodium 4.0.2+1、sqlite3 3.3.4、hooks 1.0.3，且无 dependency_overrides。
- Windows x64 与 Android API 29+ 构建通过；运行时 PRAGMA cipher_version 非空。
- 普通 sqlite3 无法读取索引；错误密钥失败；数据库文件不包含 fixture 明文。
- 运行 ADR-0005/0006 的全部密码学、来源、篡改和恢复测试。

## 安全/隐私影响

不改变用户数据格式、密码算法、网络或遥测。旧版 sqlite3 增加供应链维护负担，必须以锁定 hash、SBOM、漏洞扫描与后续 SDK 升级计划缓解。
