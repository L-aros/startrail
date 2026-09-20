import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

import 'canonical_json.dart';

const _headerMagic = <int>[0x53, 0x54, 0x56, 0x4c, 0x54, 0x00, 0x01];
const _prefixLength = 11;
const _maxPayloadLength = 16 * 1024;

final class VaultHeader {
  VaultHeader({
    required this.vaultUuid,
    required Uint8List salt,
    required Uint8List wrapNonce,
    required Uint8List wrappedMasterKey,
  }) : salt = Uint8List.fromList(salt),
       wrapNonce = Uint8List.fromList(wrapNonce),
       wrappedMasterKey = Uint8List.fromList(wrappedMasterKey);

  final String vaultUuid;
  final Uint8List salt;
  final Uint8List wrapNonce;
  final Uint8List wrappedMasterKey;
}

final class VaultHeaderCodec {
  const VaultHeaderCodec();

  Uint8List encode(VaultHeader header) {
    _validateLengths(header);
    uuidBytes(header.vaultUuid);
    final payload = encodeCanonicalJson(_toJson(header));
    final output = Uint8List(_prefixLength + payload.length);
    output.setRange(0, _headerMagic.length, _headerMagic);
    ByteData.sublistView(output).setUint32(7, payload.length);
    output.setRange(_prefixLength, output.length, payload);
    return output;
  }

  VaultHeader decode(Uint8List bytes) {
    if (bytes.length < _prefixLength) throw const CorruptVaultDataFailure();
    for (var i = 0; i < _headerMagic.length; i++) {
      if (bytes[i] != _headerMagic[i]) {
        throw const UnsupportedVaultFormatFailure();
      }
    }
    final length = ByteData.sublistView(bytes).getUint32(7);
    if (length > _maxPayloadLength || bytes.length != _prefixLength + length) {
      throw const CorruptVaultDataFailure();
    }
    final payload = Uint8List.sublistView(bytes, _prefixLength);
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
      if (kdf['algorithm'] != 'argon2id13' ||
          kdf['iterations'] != 3 ||
          kdf['memory_kib'] != 65536 ||
          kdf['parallelism'] != 1 ||
          wrap['algorithm'] != 'xchacha20poly1305-ietf') {
        throw const UnsupportedVaultFormatFailure();
      }
      final header = VaultHeader(
        vaultUuid: decoded['vault_uuid'] as String,
        salt: _decodeBase64(kdf['salt']),
        wrapNonce: _decodeBase64(wrap['nonce']),
        wrappedMasterKey: _decodeBase64(wrap['ciphertext']),
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

Map<String, Object?> _toJson(VaultHeader header) => {
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
    'ciphertext': _encodeBase64(header.wrappedMasterKey),
    'nonce': _encodeBase64(header.wrapNonce),
  },
};

void _validateLengths(VaultHeader header) {
  if (header.salt.length != 16 ||
      header.wrapNonce.length != 24 ||
      header.wrappedMasterKey.length != 48) {
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

Uint8List uuidBytes(String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(value)) {
    throw const FormatException('UUID must be lowercase canonical text');
  }
  final compact = value.replaceAll('-', '');
  return Uint8List.fromList([
    for (var i = 0; i < compact.length; i += 2)
      int.parse(compact.substring(i, i + 2), radix: 16),
  ]);
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
