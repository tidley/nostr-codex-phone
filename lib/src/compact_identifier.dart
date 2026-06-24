String compactIdentifier(String value) {
  if (value.length <= 18) return value;
  return '${value.substring(0, 10)}...${value.substring(value.length - 6)}';
}
