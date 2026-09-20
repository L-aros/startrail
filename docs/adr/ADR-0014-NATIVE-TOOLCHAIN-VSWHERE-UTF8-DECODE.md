# ADR-0014：native_toolchain_c 的 vswhere UTF-8 解码

状态：**Accepted**；日期：2026-09-20。

## 背景

ADR-0008 的 sodium 单行补丁已实现并通过离线差异验证。继续执行 Windows OpenSSL/SQLCipher 构建时，锁定的 `native_toolchain_c 0.18.0` 在三个目标架构上均于编译前失败：它虽然向 `vswhere.exe` 传递了 `-utf8`，但通用 `runProcess` 仍用 Dart `systemEncoding` 分块解码 stdout。中文 Visual Studio 描述被错误解码后产生 JSON 控制字符，`json.decode` 抛出 `FormatException`。

设置 `chcp 65001`、PowerShell `OutputEncoding` 和 `Console.OutputEncoding` 后复测结果不变。该依赖同时是 sqlite3 原生构建钩子的关键组成，不能通过修改产品区域设置规避。

## 决策

完整 vendor `native_toolchain_c 0.18.0`，原始 pub archive SHA-256 为 `8aaead321425bd3f03bd5894aa27c8ea6993eab95531da7e59f5d39c6e5708ec`。只进行以下构建期修改：

1. `runProcess` 增加默认值为 `systemEncoding` 的可选 `Encoding outputEncoding` 参数；
2. stdout/stderr 使用该参数解码，保持所有既有调用行为不变；
3. 仅 `VisualStudioResolver` 的 `vswhere -utf8` 调用传入 `utf8`。

仓库保存原始 pub archive，并提供离线验证器，保证除此补丁外 vendor 文件集合和字节均与上游一致。应用与各 package 通过 path override 使用此固定副本。补丁应提交上游；升级到包含等价修复且兼容当前 hooks API 的版本后移除 vendor。

## 备选

- 修改系统区域或永久切换控制台代码页：影响整机且实测无效，拒绝。
- 修改 Pub cache：不可复现并污染其他项目，拒绝。
- 在 OpenSSL 构建脚本硬编码 Visual Studio 路径：只绕过一次构建，应用 native-assets 构建仍会失败，拒绝。
- 升级到 `native_toolchain_c 0.19.x`：涉及 hooks/code_assets 主版本联动，超出 Milestone 1 的最小变更范围，另行评估。

## 后果

增加一个需要跟踪安全更新的 vendor 构建依赖。补丁不进入产品运行时，不改变 SQLite、SQLCipher、OpenSSL、libsodium 二进制算法或 Vault 格式。

## 迁移/回滚

不涉及用户数据迁移。移除 path override 和 vendor 目录即可回滚；回滚后中文 Windows 原生构建恢复为确定失败。

## 测试

- 用包含中文 `displayName`/`description` 的固定 vswhere JSON 字节测试 UTF-8 解码。
- 离线验证 vendor 与原始 archive 仅存在批准的解码补丁。
- 中文 Windows 上解析真实 vswhere 输出并完成 OpenSSL x64 静态构建。
- 完成 Windows Flutter 构建，并检查 SQLCipher raw-key 与 libsodium 符号。
- WSL/Android 原有构建和密码学测试不回归。

## 安全/隐私影响

不新增网络、遥测或用户数据处理。构建日志不得记录 Vault 路径、密钥、对象名或 fixture 正文。固定依赖来源、许可证、hash 与补丁差异进入第三方清单。
