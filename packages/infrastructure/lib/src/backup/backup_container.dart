import 'dart:typed_data';

/// Length in bytes of the manifest nonce stored inline in the container.
const int backupManifestNonceBytes = 24;

/// Upper bound for the plaintext header payload.
const int backupMaxHeaderLength = 16 * 1024;

/// Upper bound for the sealed manifest ciphertext.
const int backupMaxManifestLength = 16 * 1024 * 1024;

/// Encodes [value] as an unsigned 64-bit big-endian integer.
Uint8List encodeUint64Be(int value) {
  final bytes = Uint8List(8);
  ByteData.sublistView(bytes).setUint64(0, value);
  return bytes;
}

/// Decodes an unsigned 64-bit big-endian integer.
int decodeUint64Be(Uint8List bytes) => ByteData.sublistView(bytes).getUint64(0);
