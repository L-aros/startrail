# Android 平台

最低 Android 10 (API 29)。使用 scoped storage/系统文件选择器导入导出，不请求全盘存储；相机、麦克风与通知权限按功能即时请求并提供拒绝路径。VMK 的设备包装材料使用 Android Keystore，要求硬件支持时优先硬件后端；Keystore 失效不能删除 Vault，只要求用户密码重新解锁。

后台同步须经用户启用并使用 WorkManager 的网络/电量约束；不得绕过系统限制持续运行。发布使用签名 App Bundle，版本单调递增，符合 UPDATE_PROTOCOL 的渠道保证。应用切后台/锁屏时遮挡敏感页面并尽快释放明文状态。
