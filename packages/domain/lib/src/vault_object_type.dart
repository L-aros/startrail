enum VaultObjectType {
  entry(1),
  tombstone(2),
  attachmentMetadata(3),
  manifest(4),
  blob(5);

  const VaultObjectType(this.wireValue);

  final int wireValue;

  static VaultObjectType? fromWireValue(int value) {
    for (final type in values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}
