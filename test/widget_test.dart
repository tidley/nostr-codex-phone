import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nostr_codex_phone/main.dart';

void main() {
  test('app widget is available', () {
    expect(const NostrCodexApp(), isA<StatelessWidget>());
  });

  test('cleans markdown before text to speech', () {
    final spoken = cleanTextForSpeech('''
# Result

**Important bits**

- first item
- `second item`

Use [the docs](https://example.com).
''');

    expect(spoken, isNot(contains('**')));
    expect(spoken, isNot(contains('- first')));
    expect(spoken, isNot(contains('`')));
    expect(spoken, contains('Important bits'));
    expect(spoken, contains('first item'));
    expect(spoken, contains('second item'));
    expect(spoken, contains('the docs'));
  });

  test('converts bridge unsigned integers before json encoding', () {
    final converted = bridgeUIntToJsonInt(BigInt.from(90281152));

    expect(converted, 90281152);
    expect(jsonEncode({'size': converted}), '{"size":90281152}');
  });

  test('rejects negative bridge unsigned integers', () {
    final negative = BigInt.from(-1);

    expect(() => bridgeUIntToJsonInt(negative), throwsArgumentError);
  });
}
