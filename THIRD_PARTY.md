# 第三方组件清单

实现开始前维护下表；发布时以生成的 SBOM 和实际 lockfile 为准。

| 组件 | 版本 | 许可证 | 用途 | 审查状态 |
|---|---:|---|---|---|
| Flutter SDK | 3.41.6 | BSD-3-Clause | Android/Windows 客户端运行时 | 已锁定开发基线 |
| Dart SDK | 3.11.4 | BSD-3-Clause | 共享产品层语言与工具链 | 已锁定开发基线 |
| flutter_lints | 6.0.0 | BSD-3-Clause | 仅开发期静态分析规则 | 待 lockfile 验证 |
| sodium / libsodium | 4.0.2+1（vendored patch） / 1.0.21 | BSD-3-Clause, ISC | Argon2id、XChaCha20-Poly1305、CSPRNG、安全密钥内存 | ADR-0006/0008 Accepted；原始 pub archive hash 与单行 Windows 构建补丁可离线审计 |
| sqlite3 / SQLCipher / OpenSSL | 3.3.4+startrail.1 / 4.16.0 / 3.6.2 | MIT / BSD-style / Apache-2.0 | 加密派生索引；raw-key 原生绑定 | ADR-0013 Accepted；源码、hash、补丁、WSL 行为和 Android 三 ABI APK 已验证；Windows 待门禁 |
| native_toolchain_c | 0.18.0（vendored patch） | BSD-3-Clause | Dart/Flutter 原生 C 编译工具发现与调用 | ADR-0014 Accepted；原始 pub archive hash 与定点 UTF-8 解码补丁可离线审计；不进入产品运行时 |
| ffi | 2.2.0 | BSD-3-Clause | POSIX 目录 fsync 平台 adapter；不处理网络或内容语义 | 已为 sodium/sqlite3 间接依赖；Linux/Android API |
| crypto | 3.0.7 | BSD-3-Clause | Manifest 密文字节 SHA-256 标识与 HEAD 完整性验证 | 已为工具链间接依赖；纯 Dart、无网络行为 |

固定来源与 SHA-256：
- sodium 4.0.2+1 pub archive `19e3153ef4d1d10087d78d551d78e56909d159047a578ec692814c65ca450dfc`；仓库 patch 仅在 `windows_builder.dart` 的 vswhere 参数增加 `-utf8`，不修改 libsodium 源码或运行时 API。
- native_toolchain_c 0.18.0 pub archive `8aaead321425bd3f03bd5894aa27c8ea6993eab95531da7e59f5d39c6e5708ec`；仅为通用进程捕获增加默认保持兼容的输出编码参数，并在 `vswhere -utf8` 调用显式选择 UTF-8。

- sqlite3.dart tag `sqlite3-3.3.4`，commit `4a752b1a4281e315ec50a6535212cb4c9183356e`；pub archive `752d9d746052359a2022f588bb979f2e7c4e0f9e4b6a1c3121f7626a1574974b`。
- SQLCipher 4.16.0 source archive `9f51a0960cc3cebaea62ff2bfa2ec3ef502b1be808d562d89cb876a18ed09d9c`；生成的 amalgamation `0c8371853e124f20bb7728368559fe743ac3d1f0b97d317ba68b70bfe802bcb2`。
- OpenSSL 3.6.2 source archive `aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f`。
- Android OpenSSL `libcrypto.a`：arm `7526923d16d44b8b333c1c8df908329845c68513747653fbfc2941ff3f01dcee`；arm64 `2efa5ceb599d186dd168b06b46b6193be239efc47499962c76cfe57a954e7750`；ia32 `9f11dea68de813713bf961ae1e6daaba0e94639a7b8cbfb8e7a4d2570b98c9a4`；x64 `dc79de3f004a46b0584d1836e50779ee7703036e7406040ab0f0a292be831c71`。
- Windows x64 OpenSSL `libcrypto.lib`：`c4a78a6da92aa7286563cfdcd5463051a54b60caf7e171c0f7ddda6aee4586eb`；使用 OpenSSL 官方 MSVC 配置声明的 `ws2_32`、`gdi32`、`advapi32`、`crypt32`、`user32` 系统库。

Android 静态库由 OpenSSL 3.6.2 官方源码、Android NDK 28.2.13676358 及 sqlite3.dart 3.3.4 官方 `tool/build_openssl.dart` 生成。构建钩子按目标 ABI 选择仓库内头文件和静态库，不在应用构建期间下载二进制。

每次新增/升级必须验证许可证兼容、已知漏洞、维护状态、Android/Windows 支持和是否传输数据。
