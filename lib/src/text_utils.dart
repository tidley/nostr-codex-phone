String cleanTextForSpeech(String text) {
  var cleaned = text.replaceAll('\r\n', '\n');

  cleaned = cleaned.replaceAllMapped(
    RegExp(r'```[^\n]*\n?([\s\S]*?)```'),
    (_) => '\ncode block.\n',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s{0,3}\d+[.)]\s+', multiLine: true),
    '',
  );
  cleaned = cleaned.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'\*\*(.*?)\*\*'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'(^|[^\w])__([^_\n]+)__($|[^\w])', multiLine: true),
    (match) => '${match.group(1)}${match.group(2)}${match.group(3)}',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'\*(.*?)\*'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'(^|[^\w])_([^_\n]+)_($|[^\w])', multiLine: true),
    (match) => '${match.group(1)}${match.group(2)}${match.group(3)}',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'~~(.*?)~~'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true),
    '',
  );
  cleaned = cleaned
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return _speakTechnicalText(cleaned).trim();
}

String _speakTechnicalText(String text) {
  var spoken = text;

  spoken = spoken.replaceAllMapped(
    RegExp(r'\bNumber\(([^)]*)\)'),
    (match) => 'Number of ${match.group(1) ?? ''}',
  );
  spoken = spoken.replaceAllMapped(
    RegExp(r'\barr\[(\d+)\]'),
    (match) => 'array index ${_numberWords(match.group(1)!)}',
  );
  spoken = spoken.replaceAllMapped(
    RegExp(r'\b([A-Za-z][A-Za-z0-9_]*)\[(\d+)\]'),
    (match) => '${match.group(1)} index ${_numberWords(match.group(2)!)}',
  );
  spoken = spoken.replaceAllMapped(
    RegExp(r'!([A-Za-z][A-Za-z0-9_]*)'),
    (match) => 'not ${match.group(1)}',
  );
  const operators = {
    r'>=': ' greater than or equal to ',
    r'<=': ' less than or equal to ',
    r'||': ' or ',
    r'&&': ' and ',
    r'=': ' equals ',
  };
  for (final entry in operators.entries) {
    spoken = spoken.replaceAll(entry.key, entry.value);
  }

  spoken = spoken.replaceAllMapped(RegExp(r'\b[A-Za-z][A-Za-z0-9_]*\b'), (
    match,
  ) {
    final word = match.group(0)!;
    final needsSpeech =
        word.contains('_') ||
        RegExp(r'[a-z0-9][A-Z]').hasMatch(word) ||
        _spokenReplacement(word) != null;
    return needsSpeech ? _speakIdentifier(word) : word;
  });

  spoken = spoken.replaceAllMapped(
    RegExp(r'\b(\d+)ms\b', caseSensitive: false),
    (match) => '${_numberWords(match.group(1)!)} milliseconds',
  );
  spoken = spoken.replaceAllMapped(
    RegExp(r'\b(\d+)\s+minutes?\b', caseSensitive: false),
    (match) => '${_numberWords(match.group(1)!)} minutes',
  );
  spoken = spoken.replaceAllMapped(
    RegExp(r'\b(\d+)\s+baud\b', caseSensitive: false),
    (match) => '${_numberWords(match.group(1)!)} baud',
  );
  spoken = spoken.replaceAllMapped(
    RegExp(r'\b\d+\b'),
    (match) => _numberWords(match.group(0)!),
  );

  return spoken
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '.\n')
      .replaceAll(RegExp(r'\.{2,}'), '.')
      .trim();
}

String _speakIdentifier(String word) {
  final wholeReplacement = _spokenReplacement(word);
  if (wholeReplacement != null) return wholeReplacement;

  final spaced = word
      .replaceAll('_', ' ')
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      );

  return spaced
      .split(' ')
      .map((part) {
        final replacement = _spokenReplacement(part);
        if (replacement != null) return replacement;
        return part.toLowerCase();
      })
      .join(' ');
}

String? _spokenReplacement(String word) {
  for (final entry in _technicalSpeechReplacements.entries) {
    if (entry.key.toLowerCase() != word.toLowerCase()) continue;
    if (entry.key != 'repo' && word == word.toLowerCase()) return null;
    return entry.value;
  }
  return null;
}

const _technicalSpeechReplacements = {
  'GNSS': 'G N S S',
  'GGA': 'G G A',
  'NMEA': 'N M E A',
  'BCM': 'B C M',
  'OTA': 'O T A',
  'CAN': 'CAN bus',
  'BLE': 'B L E',
  'GPIO': 'G P I O',
  'UART': 'you-art',
  'RS232': 'R S two thirty two',
  'I2C': 'I squared C',
  'SPI': 'S P I',
  'MQTT': 'M Q T T',
  'JSON': 'jay-son',
  'UUID': 'U U I D',
  'API': 'A P I',
  'CLI': 'C L I',
  'repo': 'repository',
};

String _numberWords(String digits) {
  final value = int.tryParse(digits);
  if (value == null) return digits;
  if (value == 115200) return 'one fifteen two hundred';
  if (value == 232) return 'two thirty two';
  if (value < 20) {
    const small = [
      'zero',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'eleven',
      'twelve',
      'thirteen',
      'fourteen',
      'fifteen',
      'sixteen',
      'seventeen',
      'eighteen',
      'nineteen',
    ];
    return small[value];
  }
  if (value < 100) {
    const tens = {
      20: 'twenty',
      30: 'thirty',
      40: 'forty',
      50: 'fifty',
      60: 'sixty',
      70: 'seventy',
      80: 'eighty',
      90: 'ninety',
    };
    final ten = value ~/ 10 * 10;
    final rest = value % 10;
    return rest == 0 ? tens[ten]! : '${tens[ten]} ${_numberWords('$rest')}';
  }
  if (value < 1000) {
    final rest = value % 100;
    final prefix = '${_numberWords('${value ~/ 100}')} hundred';
    return rest == 0 ? prefix : '$prefix ${_numberWords('$rest')}';
  }
  return digits;
}
