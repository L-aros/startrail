# ADR-0006：Sodium 与锁定 Dart SDK 的兼容版本

状态：**Accepted**；日期：2026-09-20。

## 背景

ADR-0005 接受 sodium 4.1.0+1 / libsodium 1.0.22 与 Dart 3.11.4。实际依赖解析证明 sodium 4.1.0+1 要求 Dart 3.13，当前 Flutter 3.41.6 自带 Dart 3.11.4，因而该组合不可构建。升级 SDK 会偏离已锁定基线，并可能引入更大的 Flutter/Gradle/平台兼容风险。

## 拟议决策

Milestone 1 改为精确锁定 sodium 4.0.2+1。该版本支持 Dart 3.11，仍使用 sodium 4.x native-assets build hooks、SecureKey、Argon2id、XChaCha20-Poly1305、OS CSPRNG 和相同 adapter 边界；其嵌入的 libsodium 版本为 1.0.21。其余 ADR-0005 决策不变。

在依赖进入代码前，必须验证解析后的 lockfile、Windows 和 Android native 构建、libsodium 运行时版本、固定密码学向量及许可证。pubspec 使用精确版本而非 caret 范围，防止自动解析到要求更高 SDK 的 4.0.3+。

## 备选

- 升级到带 Dart 3.13 的 Flutter：当前 stable 基线不可用，且扩大平台回归范围，拒绝。
- sodium 3.4.7 + sodium_libs：不使用 ADR-0005 选择的 native-assets 路径，并额外引入已被替代的装载包，拒绝。
- cryptography 2.9.0：仍存在 ADR-0005 所述密钥内存生命周期弱点，拒绝。

## 后果

密码算法、格式、AD、KDF 参数及索引密钥派生均不变；变化仅是绑定包和 libsodium 补丁基线从 1.0.22 降为 1.0.21。需要持续跟踪 1.0.21 与 1.0.22 的安全差异，并在 Dart SDK 可升级时另行评估升级。

## 迁移/回滚

尚无已发布 Vault 或应用构建，无数据迁移。若平台构建、运行时版本或固定向量验证失败，移除依赖和生成产物，重新提出 ADR，不保留不可验证实现。

## 测试

- 依赖解析必须固定 sodium 4.0.2+1，禁止解析 4.0.3 及以上。
- Windows x64 与 Android API 29+ 构建并报告预期 libsodium 1.0.21；版本只用于测试断言，不写生产日志。
- 执行 ADR-0005 定义的全部 known-answer、篡改、nonce、密钥释放和跨平台 fixture 测试。

## 安全/隐私影响

不新增网络、遥测或数据流。底层库版本降低可能包含安全差异，因此批准前不得实现；批准后仍需依赖漏洞扫描与构建来源验证。
