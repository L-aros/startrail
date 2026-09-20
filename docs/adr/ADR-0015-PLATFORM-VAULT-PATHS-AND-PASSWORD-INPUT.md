# ADR-0015：平台 Vault 路径与密码输入边界

状态：**Proposed**；日期：2026-09-20。

## 背景

Milestone 1 的创建、打开与解锁 UI 必须在 Android 10+ scoped storage 和 Windows 10/11 上取得可持久访问的目录。当前共享层只接受 `Directory`，应用没有安全的默认目录或系统目录选择器。直接使用工作目录、Desktop、Temp、手写路径或请求 Android 全盘存储均违反平台规范。

Flutter 密码输入控件以不可变 Dart `String` 暂存文本，无法承诺原地清零；密码学层则要求尽快转换为可覆盖的字节并在使用后清零。Argon2id 还必须离开 UI isolate，避免 64 MiB、3 轮 KDF 阻塞界面。

## 拟议决策

1. 精确锁定 Flutter 官方 `path_provider 2.1.6`（BSD-3-Clause），仅用于取得 Android/Windows application-support 目录。默认 Vault 位于该目录下的 `vault` 子目录；不得使用临时目录、Desktop 或下载目录。
2. 精确锁定 Flutter 官方 `file_selector 1.1.0`（BSD-3-Clause；Android 实现包含 Apache-2.0 代码），仅在用户明确点击“选择位置/打开 Vault”时调用系统目录选择器。不得请求 `MANAGE_EXTERNAL_STORAGE`，不得后台扫描目录，不新增网络行为。
3. 将两个插件封装在应用平台 adapter 后；domain/application 不依赖 Flutter、插件或文件系统。系统选择器取消是正常结果，不创建、不修改任何目录。
4. 创建前展示最终位置和“密码不可恢复”说明；已有目标、不可写目录或非 Vault 目录均硬失败，不覆盖、不自动删除。
5. 密码框关闭联想、自动更正与个性化学习，默认遮挡。提交时立即 UTF-8 编码为独立 `Int8List`，清空 controller；调用方和工作 isolate 均在 `finally` 覆盖各自字节副本。不得写日志、异常、状态持久化、剪贴板或遥测。
6. Flutter/IME 内部不可变 `String` 的残留属于受控 OS/运行时无法完全消除的限制，与威胁模型中的恶意 OS/键盘记录器残余风险一致；UI 不额外保留或复制密码字符串。
7. 创建和解锁（包括 Argon2id）在短生命周期工作 isolate 执行，只返回非敏感状态；解锁后的 VMK 不跨 isolate 传递。工作 isolate 保持会话并通过不含内容的命令端口提供后续操作，锁定时 dispose 密钥并终止 isolate。

## 备选

- 仅允许手写绝对路径：Android scoped storage 不可靠且易误操作，拒绝。
- 使用工作目录或 Temp：可能不可写、被清理或泄露到工程目录，拒绝。
- 请求 Android 全盘存储权限：权限过宽，不符合最小权限，拒绝。
- 在 UI isolate 执行 Argon2id：会造成明显卡顿并违反 ADR-0005，拒绝。
- 声称 Flutter 密码 `String` 可安全清零：技术上不成立，拒绝。

## 后果

新增两个 Flutter 官方平台插件及其传递依赖，需要锁定 lockfile、记录许可证和重新执行 Android/Windows 构建。系统选择器只暴露用户明确选择的路径；路径仍视为敏感，不写日志或遥测。工作 isolate 增加会话编排复杂度，但保证 KDF 不阻塞 UI，并让锁定操作具备明确的密钥销毁边界。

## 迁移/回滚

尚无发布 Vault，无数据迁移。移除插件、平台 adapter 和 UI 接线即可回滚；已有测试 Vault 不得由回滚流程删除。未来更换路径插件或改变默认目录须重新评估已创建 Vault 的发现与迁移策略。

## 测试

- mock 平台 adapter 验证默认目录、用户取消、已有目标、不可写目录与无效 Vault 均不产生部分写入。
- Android 10+ 验证 scoped storage、无全盘权限、系统目录选择器取消/选择和重启解锁。
- Windows 10/11 验证 application-support 默认目录、目录选择器和路径含中文/空格。
- widget 测试验证密码不可恢复提示、遮挡、键盘提交、错误密码统一显示 `VAULT_AUTH_FAILED`、锁定后返回解锁页。
- 计时测试证明 Argon2id 不阻塞 UI isolate；锁定/异常后工作 isolate 终止、字节副本覆盖且 session dispose。
- Android/Windows 构建、依赖许可证扫描和日志敏感字段扫描通过。

## 安全/隐私影响

不新增网络、遥测、后台扫描或宽泛存储权限。新增本地系统目录调用；Vault 路径、密码、密钥、对象名与原始异常均不得进入日志。用户选择外部目录时，应用必须说明该位置的本地访问权限由操作系统和用户负责。
