# Windows 平台

支持 Windows 10/11 x64（ARM64 由 ADR 决定）。Vault 路径由用户选择；默认放在应用私有数据目录，不写 Desktop/Temp。以 DPAPI（当前用户范围）保护 VMK 的设备包装材料；DPAPI 失败仍可用密码打开 Vault。

文件替换使用同卷临时文件和原子 rename；处理防病毒/锁定文件时可重试且不覆盖。安装包以 Authenticode 签名；更新遵循 UPDATE_PROTOCOL。支持键盘导航、系统高对比与缩放；关闭窗口前处理未保存编辑。
