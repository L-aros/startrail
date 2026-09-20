# 开发环境

要求：Flutter stable、Dart stable、Android Studio/SDK（Android 10+ emulator）、Visual Studio 2022 Build Tools（Windows Desktop C++）、Git、受控的测试 R2 bucket。实现仓库建立后执行 `flutter doctor`，锁定 SDK/依赖，禁止把凭据写入源码。
Windows Flutter 插件构建需要启用系统 Developer Mode，以允许依赖使用符号链接。应用层 `pubspec.yaml` 必须保留 `hooks.user_defines.sqlite3` 的 SQLCipher 源码、OpenSSL 与 codec defines；native-assets 配置不会从依赖包自动传播到顶层应用。发布构建须检查 `sqlite3_key_v2`/`sqlite3_rekey_v2` 导出及 SQLCipher 版本字符串，禁止以普通 SQLite 产物通过验收。

本地配置使用未提交的 `.env.local` 或平台 secret store；只提供 `.env.example` 空占位。开发 Vault 与 fixture 必须由测试工具随机生成、使用公开无意义文本。建议命令门禁：格式化、`flutter analyze`、单元测试、集成测试、golden/accessibility 测试、依赖审计、SBOM、secret scan。
