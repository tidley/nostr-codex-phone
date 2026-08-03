import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nostr_codex_phone/main.dart';
import 'package:nostr_codex_phone/src/bridge_json.dart';
import 'package:nostr_codex_phone/src/repo_choice.dart';
import 'package:nostr_codex_phone/src/repo_target.dart';
import 'package:nostr_codex_phone/src/text_utils.dart';
import 'package:nostr_codex_phone/src/tool_result_models.dart';
import 'package:nostr_codex_phone/src/voice_recording.dart';
import 'package:nostr_codex_phone/src/workspace_models.dart';

void main() {
  test('app widget is available', () {
    expect(const NostrCodexApp(), isA<StatefulWidget>());
  });

  testWidgets('incoming group call prompt shows context and actions', (
    tester,
  ) async {
    var answered = false;
    var rejected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncomingCallPrompt(
            isGroupCall: true,
            caller: 'Ada',
            channel: 'Mobile team',
            onAnswer: () => answered = true,
            onReject: () => rejected = true,
          ),
        ),
      ),
    );

    expect(find.text('Incoming channel call'), findsOneWidget);
    expect(find.text('Ada invited you to Mobile team'), findsOneWidget);
    await tester.tap(find.text('Answer'));
    await tester.tap(find.text('Reject'));
    expect(answered, isTrue);
    expect(rejected, isTrue);
  });

  testWidgets('incoming direct call prompt shows caller and actions', (
    tester,
  ) async {
    var answered = false;
    var rejected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncomingCallPrompt(
            isGroupCall: false,
            caller: 'Lin',
            onAnswer: () => answered = true,
            onReject: () => rejected = true,
          ),
        ),
      ),
    );

    expect(find.text('Incoming call'), findsOneWidget);
    expect(find.text('Lin is calling you'), findsOneWidget);
    await tester.tap(find.text('Answer'));
    await tester.tap(find.text('Reject'));
    expect(answered, isTrue);
    expect(rejected, isTrue);
  });

  testWidgets('main and thread composers keep separate drafts and sends', (
    tester,
  ) async {
    final mainController = TextEditingController();
    final threadController = TextEditingController();
    final mainFocus = FocusNode();
    final threadFocus = FocusNode();
    var mainSends = 0;
    var threadSends = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Material(
          child: Column(
            children: [
              WorkspaceComposer(
                composer: mainController,
                composerFocus: mainFocus,
                hintText: 'Message # workspace',
                mentionOptions: const <WorkspaceMention>[],
                onMentionSelected: (_) {},
                onSend: () => mainSends++,
                onAttach: () async {},
              ),
              WorkspaceComposer(
                composer: threadController,
                composerFocus: threadFocus,
                hintText: 'Reply in thread',
                mentionOptions: const <WorkspaceMention>[],
                onMentionSelected: (_) {},
                onSend: () => threadSends++,
                onAttach: () async {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('Enter to send. Ctrl+Enter for new line.'),
      findsNWidgets(2),
    );
    await tester.enterText(find.byType(TextField).at(0), 'Main message');
    await tester.pump();
    expect(mainFocus.hasFocus, isTrue);
    final mainField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(mainField.textInputAction, TextInputAction.send);
    mainField.onSubmitted!('Main message');
    await tester.pump();

    expect(mainSends, 1);
    expect(mainController.text, 'Main message');

    await tester.enterText(find.byType(TextField).at(1), 'Thread reply');
    await tester.pump();
    final threadField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(threadField.textInputAction, TextInputAction.send);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Thread reply\n',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();

    expect(threadController.text, 'Thread reply\n');
    expect(threadSends, 0);
    threadField.onSubmitted!('Thread reply\n');

    expect(mainController.text, 'Main message');
    expect(threadController.text, 'Thread reply\n');
    expect(mainSends, 1);
    expect(threadSends, 1);

    mainController.dispose();
    threadController.dispose();
    mainFocus.dispose();
    threadFocus.dispose();
  });

  testWidgets('composer exposes voice transcription state without sending', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Draft stays here');
    final focus = FocusNode();
    var sends = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: WorkspaceComposer(
            composer: controller,
            composerFocus: focus,
            hintText: 'Message',
            mentionOptions: const <WorkspaceMention>[],
            onMentionSelected: (_) {},
            onSend: () => sends++,
            onAttach: () async {},
            voiceTranscribing: true,
            onVoicePressed: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Transcribing voice'), findsOneWidget);
    expect(find.text('Transcribing voice...'), findsOneWidget);
    expect(controller.text, 'Draft stays here');
    expect(sends, 0);

    controller.dispose();
    focus.dispose();
  });

  testWidgets('thread pane resize handle reports inverse horizontal drag', (
    tester,
  ) async {
    final deltas = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.center,
            child: ThreadPaneResizeHandle(onResize: deltas.add),
          ),
        ),
      ),
    );

    final handle = find.byType(ThreadPaneResizeHandle);
    expect(
      tester
          .widget<MouseRegion>(
            find.descendant(of: handle, matching: find.byType(MouseRegion)),
          )
          .cursor,
      SystemMouseCursors.resizeLeftRight,
    );

    await tester.drag(handle, const Offset(-24, 0));

    expect(deltas, isNotEmpty);
    expect(deltas.reduce((sum, delta) => sum + delta), greaterThan(0));
  });

  testWidgets('sidebar pane resize handle reports horizontal drag', (
    tester,
  ) async {
    final deltas = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.center,
            child: SidebarPaneResizeHandle(onResize: deltas.add),
          ),
        ),
      ),
    );

    final handle = find.byType(SidebarPaneResizeHandle);
    expect(
      tester
          .widget<MouseRegion>(
            find.descendant(of: handle, matching: find.byType(MouseRegion)),
          )
          .cursor,
      SystemMouseCursors.resizeLeftRight,
    );
    expect(
      tester
          .widget<Semantics>(
            find.descendant(of: handle, matching: find.byType(Semantics)),
          )
          .properties
          .label,
      'Resize sidebar',
    );

    await tester.drag(handle, const Offset(24, 0));

    expect(deltas, isNotEmpty);
    expect(deltas.reduce((sum, delta) => sum + delta), greaterThan(0));
  });

  testWidgets(
    'composer disables send until text exists and supports multiline',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      var sends = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Material(
            child: WorkspaceComposer(
              composer: controller,
              composerFocus: focus,
              hintText: 'Message # workspace',
              mentionOptions: const [],
              onMentionSelected: (_) {},
              onSend: () => sends++,
              onAttach: () async {},
            ),
          ),
        ),
      );

      expect(find.text('Enter for new line'), findsOneWidget);
      final sendButton = find.ancestor(
        of: find.byIcon(Icons.send),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'First line\nSecond line');
      await tester.pump();

      expect(controller.text, 'First line\nSecond line');
      expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
      await tester.tap(find.byIcon(Icons.send));
      expect(sends, 1);

      controller.dispose();
      focus.dispose();
    },
  );

  testWidgets(
    'desktop composer does not send while an IME composition is active',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      var sends = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Material(
            child: WorkspaceComposer(
              composer: controller,
              composerFocus: focus,
              hintText: 'Message # workspace',
              mentionOptions: const [],
              onMentionSelected: (_) {},
              onSend: () => sends++,
              onAttach: () async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      controller.value = const TextEditingValue(
        text: 'Draft',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      tester.widget<TextField>(find.byType(TextField)).onSubmitted!('Draft');

      expect(sends, 0);

      controller.dispose();
      focus.dispose();
    },
  );

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

  test('removes URL schemes before text to speech', () {
    final spoken = cleanTextForSpeech(
      'Install from https://github.com/tidley/nostr-codex-phone/releases.',
    );

    expect(
      spoken,
      contains(
        'github.com slash tidley slash nostr-codex-phone slash releases.',
      ),
    );
    expect(spoken, isNot(contains('https')));
  });

  test('spells arbitrary uppercase initialisms', () {
    final spoken = cleanTextForSpeech(
      'Enable SSO for the CRM, SDK, and A.P.I.',
    );

    expect(spoken, contains('S S O'));
    expect(spoken, contains('C R M'));
    expect(spoken, contains('S D K'));
    expect(spoken, contains('A P I'));
  });

  test('names portable mathematical and comparison symbols', () {
    final spoken = cleanTextForSpeech(
      'enabled != OK; x ≠ y; 3 × 2 ≈ 6 ÷ 1; threshold > 5%',
    );

    expect(spoken, contains('enabled not equal to O K'));
    expect(spoken, contains('x not equal to y'));
    expect(
      spoken,
      contains('three times two approximately six divided by one'),
    );
    expect(spoken, contains('threshold greater than five percent'));
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

  test('reads Markdown tables as labeled rows', () {
    final spoken = cleanTextForSpeech('''
| Sensor | Value | Status |
| --- | ---: | --- |
| GNSS | 3.14 | OK |
| CAN | 115200 baud | Ready |
''');

    expect(spoken, contains('Table. Columns: Sensor, Value, Status.'));
    expect(
      spoken,
      contains(
        'Row one. Sensor: G N S S, Value: three point one four, Status: O K.',
      ),
    );
    expect(
      spoken,
      contains(
        'Row two. Sensor: CAN bus, Value: one fifteen two hundred baud, Status: Ready.',
      ),
    );
    expect(spoken, isNot(contains('vertical line')));
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

  test('decodes structured git and file tool results', () {
    final payload = ToolResultPayload.fromJson({
      'tool': 'git_status',
      'request_id': 'request-1',
      'workdir': '/repo',
      'data': {
        'branch': 'main',
        'clean': false,
        'latest': {'hash': 'abc123', 'subject': 'Change files'},
        'files': [
          {
            'path': 'lib/main.dart',
            'index_status': 'M',
            'worktree_status': ' ',
            'staged': true,
            'untracked': false,
          },
        ],
      },
    });

    expect(payload, isNotNull);
    final status = GitStatusResult.fromPayload(payload!);
    expect(status.branch, 'main');
    expect(status.files.single.path, 'lib/main.dart');
    expect(status.files.single.statusLabel, 'Staged');

    final file = FileContentResult.fromPayload(
      ToolResultPayload(
        tool: 'read_file',
        requestId: 'request-2',
        workdir: '/repo',
        data: const {
          'path': 'README.md',
          'content': '# Hello',
          'line_count': 1,
          'truncated': false,
        },
      ),
    );
    expect(file.path, 'README.md');
    expect(file.lineCount, 1);

    final browser = FileBrowserResult.fromPayload(
      ToolResultPayload(
        tool: 'file_browser',
        requestId: 'request-3',
        workdir: '/repo',
        data: const {
          'entries': [
            {'path': 'lib', 'is_dir': true},
            {'path': 'lib/main.dart', 'is_dir': false},
          ],
          'truncated': false,
        },
      ),
    );
    expect(browser.entries.first.isDirectory, true);
    expect(browser.entries.last.name, 'main.dart');
  });
}
