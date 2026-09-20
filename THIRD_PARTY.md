# 第三方组件清单

实现开始前维护下表；发布时以生成的 SBOM 和实际 lockfile 为准。

| 组件 | 版本 | 许可证 | 用途 | 审查状态 |
|---|---:|---|---|---|
| Flutter SDK | 3.41.6 | BSD-3-Clause | Android/Windows 客户端运行时 | 已锁定开发基线 |
| Dart SDK | 3.11.4 | BSD-3-Clause | 共享产品层语言与工具链 | 已锁定开发基线 |
| flutter_lints | 6.0.0 | BSD-3-Clause | 仅开发期静态分析规则 | 待 lockfile 验证 |
| sodium / libsodium | 4.0.2+1 / 1.0.21 | BSD-3-Clause, ISC | Argon2id、XChaCha20-Poly1305、CSPRNG、安全密钥内存 | ADR-0006 Accepted；WSL native-assets 已验证 |
| sqlite3 / SQLCipher / OpenSSL | 3.3.4+startrail.1 / 4.16.0 / 3.6.2 | MIT / BSD-style / Apache-2.0 | 加密派生索引；raw-key 原生绑定 | ADR-0013 Accepted；源码、hash、补丁和 WSL raw-key 行为已验证；Android/Windows 构建待门禁 |
| ffi | 2.2.0 | BSD-3-Clause | POSIX 目录 fsync 平台 adapter；不处理网络或内容语义 | 已为 sodium/sqlite3 间接依赖；Linux/Android API |
| crypto | 3.0.7 | BSD-3-Clause | Manifest 密文字节 SHA-256 标识与 HEAD 完整性验证 | 已为工具链间接依赖；纯 Dart、无网络行为 |

每次新增/升级必须验证许可证兼容、已知漏洞、维护状态、Android/Windows 支持和是否传输数据。
