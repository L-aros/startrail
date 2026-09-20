# sqlite3 3.3.4 StarTrail patch inventory

Upstream package: `sqlite3` 3.3.4, pub archive SHA-256
`752d9d746052359a2022f588bb979f2e7c4e0f9e4b6a1c3121f7626a1574974b`.
The release tag `sqlite3-3.3.4` resolves to commit
`4a752b1a4281e315ec50a6535212cb4c9183356e`.

The vendored version is `3.3.4+startrail.1`. Intentional differences are:

- remove the upstream monorepo-only `resolution: workspace` setting;
- add `sqlite3_key_v2` to the generated native binding and Linux export list;
- expose `Database.applySqlCipherRawKey(Uint8List)` only on the FFI API;
- allocate a native key copy, overwrite it on success or exception, then free it;
- add tests proving the temporary native copy is cleared on both paths.

No passphrase or SQL-string key API is added. Regenerate/rebase only against the
recorded upstream release, then review the complete diff before changing the
vendored version.
