# 开发环境

要求：Flutter stable、Dart stable、Android Studio/SDK（Android 10+ emulator）、Visual Studio 2022 Build Tools（Windows Desktop C++）、Git、受控的测试 R2 bucket。实现仓库建立后执行 `flutter doctor`，锁定 SDK/依赖，禁止把凭据写入源码。

本地配置使用未提交的 `.env.local` 或平台 secret store；只提供 `.env.example` 空占位。开发 Vault 与 fixture 必须由测试工具随机生成、使用公开无意义文本。建议命令门禁：格式化、`flutter analyze`、单元测试、集成测试、golden/accessibility 测试、依赖审计、SBOM、secret scan。
