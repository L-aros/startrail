# ADR-0008：Sodium Windows 构建的 vswhere UTF-8 补丁

状态：**Accepted**；日期：2026-09-20。

## 背景

sodium 4.0.2+1 的 Windows native-assets builder 调用 vswhere.exe -format json 后直接使用 Dart utf8.decoder。中文 Windows 上 vswhere 默认按系统代码页输出含中文 displayName/description 的 JSON，导致 Missing extension byte，构建在读取安装路径前失败。安装 en-US Build Tools 产品语言、设置 VSLANG、UTF-8 控制台和预初始化 Developer Command Prompt 均不能改变该调用。

官方 vswhere 提供 -utf8 参数。上游 builder 的参数列表缺少该参数，是可独立复现的构建兼容缺陷，与加密算法运行时无关。

## 决策

在仓库内维护 sodium 4.0.2+1 的最小 vendor patch，仅在 windows_builder.dart 的 vswhere 参数中增加 -utf8；不修改任何 Dart API、libsodium 源码、编译选项、密码算法或二进制内容。pubspec 通过仓库内 path 依赖引用完整、固定的上游源码快照，记录原始包 SHA-256、补丁 diff 和许可证；CI 校验 vendor 目录除该单行补丁外与上游归档一致。

该补丁应提交上游；升级到已包含等价修复且兼容当前 Dart/hooks 的正式版本后，移除 vendor 副本并单独审查。

## 备选

- 修改系统区域设置为 UTF-8：影响整机且需要重启，拒绝。
- 替换 Program Files 中的 vswhere.exe：破坏微软安装器组件，拒绝。
- 修改 Pub cache：不可复现、会影响其他项目，拒绝。
- 改用 cryptography：改变 ADR-0005 的密钥内存保证，拒绝。

## 后果

增加一个需持续同步安全修复的 vendor 依赖，但补丁面仅为构建期参数。应用运行时仍链接未修改的 libsodium 1.0.21。仓库体积和依赖审计成本上升。

## 迁移/回滚

无 Vault 数据迁移。删除 path override/vendor 目录即可回滚；回滚后中文 Windows 构建恢复为明确失败。

## 测试

- 中文 Windows 上 native-assets 构建通过，vswhere JSON 可被严格 UTF-8 解码。
- vendor 差异检查只允许新增一个 -utf8 参数。
- 对生成的 libsodium 二进制执行版本断言、上游 known-answer 测试和项目密码学向量。
- Windows/Android 构建及 SBOM/许可证扫描通过。

## 安全/隐私影响

不新增网络、遥测或用户数据流，不改变密码学运行时代码。vendor 来源、原始 hash 和差异必须可审计；任何超出单行构建参数的变化需新 ADR。
