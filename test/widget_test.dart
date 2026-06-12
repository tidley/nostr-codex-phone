import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nostr_codex_phone/main.dart';

void main() {
  test('app widget is available', () {
    expect(const NostrCodexApp(), isA<StatelessWidget>());
  });
}
