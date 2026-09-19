# ADR-0002：不可变对象与 manifest 头

状态：Accepted；日期：2026-09-20。

决定：内容对象和 manifest 不可变，HEAD 通过条件更新指向新 manifest；并发保留 sibling。备选是可变文件/last-write-wins。后果是需 GC 和冲突 UI，但避免静默丢失。验证：并发、412、取消与崩溃测试。
