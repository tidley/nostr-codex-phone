int bridgeUIntToJsonInt(BigInt value) {
  if (value.isNegative) {
    throw ArgumentError.value(value, 'value', 'integer must be non-negative');
  }
  final converted = value.toInt();
  if (BigInt.from(converted) != value) {
    throw ArgumentError.value(value, 'value', 'integer is too large for JSON');
  }
  return converted;
}
