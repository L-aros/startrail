import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

import 'canonical_json.dart';
import 'vault_header.dart';

/// Backup container magic: `STBKP\0\1`.
const backupMagic = <int>[0x53, 0x54, 0x42, 0x4b, 0x50, 0x00, 0x01];

/// Length of the fixed prefix: magic (7) + header payload length (u32be).
const backupHeaderPrefixLength = 11;

const _maxHeaderPayloadLength = 16 * 1024;

/// Plaintext backup header, structurally identical to the Vault header but
/// wrapping a per-backup Backup Key instead of the Vault Master Key.
final class BackupHeader {
  BackupHeader({
    required this.vaultUuid,
    required Uint8List salt,
    required Uint8List wrapNonce,
    required Uint8List wrappedBackupKey,
  }) : salt = Uint8List.fromList(salt),
       wrapNonce = Uint8List.fromList(wrapNonce),
       wrappedBackupKey = Uint8List.fromList(wrappedBackupKey);

  final String vaultUuid;
  final Uint8List salt;
  final Uint8List wrapNonce;
  final Uint8List wrappedBackupKey;
}

final class BackupHeaderCodec {
  const BackupHeaderCodec();

  Uint8List encode(BackupHeader header) {
    _validateLengths(header);
    uuidBytes(header.vaultUuid);
    final payload = encodeCanonicalJson(_toJson(header));
    final output = Uint8List(backupHeaderPrefixLength + payload.length);
    output.setRange(0, backupMagic.length, backupMagic);
    ByteData.sublistView(output).setUint32(7, payload.length);
    output.setRange(backupHeaderPrefixLength, output.length, payload);
    return output;
  }

  BackupHeader decode(Uint8List bytes) {
    if (bytes.length < backupHeaderPrefixLength) {
      throw const CorruptVaultDataFailure();
    }
    for (var i = 0; i < backupMagic.length; i++) {
      if (bytes[i] != backupMagic[i]) {
        throw const UnsupportedVaultFormatFailure();
      }
    }
    final length = ByteData.sublistView(bytes).getUint32(7);
    if (length > _maxHeaderPayloadLength ||
        bytes.length != backupHeaderPrefixLength + length) {
      throw const CorruptVaultDataFailure();
    }
    return decodePayload(
      Uint8List.sublistView(bytes, backupHeaderPrefixLength),
    );
  }

  /// Parses just the canonical JSON payload (without the magic/length prefix).
  /// Used by the backup opener, which reads the header fields separately from
  /// the container stream.
  BackupHeader decodePayload(Uint8List payload) {
    try {
      final decoded = jsonDecode(utf8.decode(payload, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('header payload must be an object');
      }
      if (!_bytesEqual(payload, encodeCanonicalJson(decoded))) {
        throw const FormatException('header payload is not canonical');
      }
      _expectKeys(decoded, const {'format', 'kdf', 'vault_uuid', 'wrap'});
      if (decoded['format'] != 1) {
        throw const UnsupportedVaultFormatFailure();
      }
      final kdf = _object(decoded['kdf']);
      final wrap = _object(decoded['wrap']);
      _expectKeys(kdf, const {
        'algorithm',
        'iterations',
        'memory_kib',
        'parallelism',
        'salt',
      });
      _expectKeys(wrap, const {'algorithm', 'ciphertext', 'nonce'});
      // Exact match on the v1 KDF parameters rejects both downgrade and upgrade
      // attempts; any change requires a new backup format version.
      if (kdf['algorithm'] != 'argon2id13' ||
          kdf['iterations'] != 3 ||
          kdf['memory_kib'] != 65536 ||
          kdf['parallelism'] != 1 ||
          wrap['algorithm'] != 'xchacha20poly1305-ietf') {
        throw const UnsupportedVaultFormatFailure();
      }
      final header = BackupHeader(
        vaultUuid: decoded['vault_uuid'] as String,
        salt: _decodeBase64(kdf['salt']),
        wrapNonce: _decodeBase64(wrap['nonce']),
        wrappedBackupKey: _decodeBase64(wrap['ciphertext']),
      );
      uuidBytes(header.vaultUuid);
      _validateLengths(header);
      return header;
    } on VaultFailure {
      rethrow;
    } on Object {
      throw const CorruptVaultDataFailure();
    }
  }
}

Map<String, Object?> _toJson(BackupHeader header) => {
  'format': 1,
  'kdf': {
    'algorithm': 'argon2id13',
    'iterations': 3,
    'memory_kib': 65536,
    'parallelism': 1,
    'salt': _encodeBase64(header.salt),
  },
  'vault_uuid': header.vaultUuid,
  'wrap': {
    'algorithm': 'xchacha20poly1305-ietf',
    'ciphertext': _encodeBase64(header.wrappedBackupKey),
    'nonce': _encodeBase64(header.wrapNonce),
  },
};

void _validateLengths(BackupHeader header) {
  if (header.salt.length != 16 ||
      header.wrapNonce.length != 24 ||
      header.wrappedBackupKey.length != 48) {
    throw const CorruptVaultDataFailure();
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException();
  return value;
}

void _expectKeys(Map<String, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    throw const UnsupportedVaultFormatFailure();
  }
}

String _encodeBase64(Uint8List value) =>
    base64Url.encode(value).replaceAll('=', '');

Uint8List _decodeBase64(Object? value) {
  if (value is! String || value.contains('=')) throw const FormatException();
  final padding = '=' * ((4 - value.length % 4) % 4);
  final decoded = base64Url.decode('$value$padding');
  if (_encodeBase64(decoded) != value) throw const FormatException();
  return decoded;
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
