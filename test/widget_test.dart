import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nostr_codex_phone/main.dart';
import 'package:nostr_codex_phone/src/bridge_json.dart';
import 'package:nostr_codex_phone/src/repo_choice.dart';
import 'package:nostr_codex_phone/src/repo_target.dart';
import 'package:nostr_codex_phone/src/text_utils.dart';
import 'package:nostr_codex_phone/src/voice_recording.dart';

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

  test('preprocesses technical text before text to speech', () {
    final spoken = cleanTextForSpeech('''
Zero-quality GGA means no GNSS fix.
quality = 0
validFix = false
arr[6]
Number(validFix)
!validFix || validFix && quality >= 0 <= 1
lastGnssDataAt
no_fix_watchdog
100ms
115200 baud
repo API JSON RS232 I2C UART CAN BLE
''');

    expect(spoken, contains('G G A'));
    expect(spoken, contains('G N S S'));
    expect(spoken, contains('quality equals zero'));
    expect(spoken, contains('valid fix equals false'));
    expect(spoken, contains('array index six'));
    expect(spoken, contains('Number of valid fix'));
    expect(spoken, contains('not valid fix or valid fix and quality'));
    expect(spoken, contains('greater than or equal to zero'));
    expect(spoken, contains('less than or equal to one'));
    expect(spoken, contains('last G N S S data at'));
    expect(spoken, contains('no fix watchdog'));
    expect(spoken, contains('one hundred milliseconds'));
    expect(spoken, contains('one fifteen two hundred baud'));
    expect(spoken, contains('repository A P I jay-son'));
    expect(spoken, contains('R S two thirty two'));
    expect(spoken, contains('I squared C'));
    expect(spoken, contains('you-art CAN bus B L E'));
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

  test('estimates voice transcription duration from audio length', () {
    final short = estimateVoiceTranscriptionDuration(
      const Duration(seconds: 1),
    );
    final medium = estimateVoiceTranscriptionDuration(
      const Duration(seconds: 30),
    );
    final long = estimateVoiceTranscriptionDuration(const Duration(minutes: 5));

    expect(short, const Duration(milliseconds: 4804));
    expect(medium, greaterThan(short));
    expect(long, const Duration(seconds: 90));
  });

  test('round trips extracted repo target and repo choice models', () {
    final target = RepoTarget.fromJson({
      'id': 'phone',
      'name': '',
      'pubkey': 'npub1234567890abcdef123456',
      'relays': [' wss://relay.example ', ''],
      'workdir': '/home/tom/code/phone',
      'parent_relays': ['wss://parent.example'],
      'opencode_session_id': 'ses_123',
      'opencode_session_title': 'Release work',
      'is_master_session': true,
    });
    final choice = RepoChoice.fromJson({
      'name': 'phone',
      'path': '/home/tom/code/phone',
      'relative_path': 'phone',
      'is_git_repo': true,
    });

    expect(target, isNotNull);
    expect(target!.displayName, 'npub123456...123456');
    expect(target.toJson()['relays'], ['wss://relay.example']);
    expect(target.toJson()['opencode_session_id'], 'ses_123');
    expect(target.toJson()['opencode_session_title'], 'Release work');
    expect(target.toJson()['is_master_session'], true);
    expect(choice?.displayName, 'phone');
    expect(choice?.toJson()['is_git_repo'], true);
  });
}
