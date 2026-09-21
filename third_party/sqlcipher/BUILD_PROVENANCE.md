# SQLCipher build provenance

This directory contains the inputs selected by ADR-0013.

| Input | Version/source | SHA-256 |
|---|---|---|
| SQLCipher source archive | official GitHub tag `v4.16.0` | `9f51a0960cc3cebaea62ff2bfa2ec3ef502b1be808d562d89cb876a18ed09d9c` |
| generated `sqlcipher_amalgamation.c` | `./configure && make sqlite3.c -j` | `0c8371853e124f20bb7728368559fe743ac3d1f0b97d317ba68b70bfe802bcb2` |
| generated `sqlite3.h` | same build | `126a6cdd1a2b2b3f47ec1952defc8e2434ebecfa239f917463e11fdffcfe16dd` |
| generated `sqlite3ext.h` | same build | `ac9645e5c9ff0cf176efdd6e75cb5e98f46295d38e02db5c4d208826a39ab4be` |
| OpenSSL source archive | official GitHub release `openssl-3.6.2` | `aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f` |

The SQLCipher archive is stored at `source/sqlcipher-v4.16.0.zip`; the OpenSSL
archive is fetched and hash-verified by platform build preparation because its
generated static libraries are platform-specific.

The compile definitions match sqlite3.dart tag `sqlite3-3.3.4`:

- `SQLITE_HAS_CODEC`
- `SQLITE_TEMP_STORE=2`
- `SQLITE_EXTRA_INIT=sqlcipher_extra_init`
- `SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown`
- `HAVE_USLEEP`
- `SQLITE_USE_URI`
- `SQLITE_ENABLE_MEMORY_MANAGEMENT`

The build must link OpenSSL 3.6.2 `libcrypto`, export `sqlite3_key_v2`, and must
not export `sqlite3_rekey_v2`. Android and Windows use static libraries
produced from the pinned archive before their release gates are considered
satisfied.

WSL/Linux x64 currently builds against the system OpenSSL 3 ABI, so its only
platform-specific inputs are the link flags `crypto` and `m`. As required by
ADR-0013, that difference is limited to the OpenSSL library path and the
necessary link flags, and it is not yet ABI-pinned to the recorded OpenSSL
3.6.2 archive; pinning Linux as well remains an open item for the release gate.
