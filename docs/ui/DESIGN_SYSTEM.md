# 设计系统

风格为安静、温暖、可读，避免将私密记录做成社交动态。token 以语义命名：`surface/background/elevated`、`text/primary/secondary/danger`、`accent/primary`、`status/success/warning/error`，支持亮/暗主题与高对比度；不在业务代码硬编码色值。

最小组件：AppShell、TimelineCard、EntryEditor、TagChip、AttachmentTile、SyncStatus、ConflictResolver、DestructiveConfirm、EmptyState、ErrorState。间距采用 4px 基准；触控目标至少 44dp；错误颜色不作为唯一信息载体。正文优先系统字体、可复制、支持系统字号。媒体默认不自动播放。
