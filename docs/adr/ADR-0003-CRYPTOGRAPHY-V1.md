# ADR-0003：v1 Argon2id + XChaCha20-Poly1305

状态：Accepted；日期：2026-09-20。

决定：依 `CRYPTOGRAPHY.md` 使用 Argon2id 保护密码、随机 VMK、XChaCha20-Poly1305 加密对象。备选为 PBKDF2、AES-GCM 或自行设计。后果是依赖成熟库，性能参数需基准测试；参数/算法变动为高风险 ADR。验证：known-answer、nonce 与篡改测试。
