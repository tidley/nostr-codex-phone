import 'package:crew/main.dart';
import 'package:crew/src/workspace_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'read' ? '1' : null,
        );
  });

  for (final direct in [false, true]) {
    testWidgets(
      '${direct ? 'direct' : 'channel'} real composers scope ThreadAgent to the selected thread',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = direct
            ? WorkspaceState.directKey('alice', 'bob')
            : 'engineering';
        final scope = direct
            ? <String, Object?>{'member_pubkey': 'bob', 'peer_pubkey': 'alice'}
            : <String, Object?>{'channel_id': 'engineering'};
        final state = WorkspaceState()
          ..apply({
            'workspace_update': {
              'action': 'snapshot',
              'channels': [
                {
                  'id': 'engineering',
                  'name': 'Engineering',
                  'members': [
                    {'pubkey': 'alice'},
                    {'pubkey': 'bob'},
                  ],
                },
              ],
              'members': [
                {'pubkey': 'alice'},
                {'pubkey': 'bob'},
              ],
              'agents': [
                {
                  'id': 'coordinator-id',
                  'name': 'A0',
                  'role': 'Task coordinator',
                },
                for (final id in ['assigned-id', 'other-id', 'foreign-id'])
                  {'id': id, 'name': 'A12', 'role': 'Conversation worker'},
              ],
              'conversation_agents': [
                {'agent_id': 'coordinator-id', ...scope},
                {'agent_id': 'assigned-id', 'parent_id': 'root', ...scope},
                {'agent_id': 'other-id', 'parent_id': 'other-root', ...scope},
                {
                  'agent_id': 'foreign-id',
                  'parent_id': 'root',
                  if (direct) ...{
                    'member_pubkey': 'alice',
                    'peer_pubkey': 'carol',
                  } else
                    'channel_id': 'other-channel',
                },
              ],
              'messages': [
                for (final id in ['root', 'other-root', 'unassigned'])
                  {
                    'id': id,
                    'sender_pubkey': 'alice',
                    'body': 'Topic $id',
                    'created_at': 1,
                    if (direct)
                      'recipient_pubkey': 'bob'
                    else
                      'channel_id': 'engineering',
                  },
              ],
            },
          });
        final requests = <Map<String, Object?>>[];
        List<TextEditingController>? previousControllers;
        for (final root in ['root', 'other-root', 'unassigned']) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: teamWorkspaceForTest(
                  workspace: state,
                  conversationKey: key,
                  threadId: root,
                  onRequest: (request) async {
                    requests.add(request);
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Both real controllers stay mounted while the active thread changes.
          final controllers = tester
              .widgetList<WorkspaceComposer>(find.byType(WorkspaceComposer))
              .map((composer) => composer.composer)
              .toList();
          expect(controllers, hasLength(2));
          if (previousControllers != null) {
            expect(controllers.first, same(previousControllers.first));
            expect(controllers.last, same(previousControllers.last));
          }
          previousControllers = controllers;
          Finder fieldFor(TextEditingController controller) =>
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    identical(widget.controller, controller),
              );
          await tester.enterText(fieldFor(controllers.first), '@');
          await tester.pumpAndSettle();
          expect(find.text('@Coordinator'), findsOneWidget);
          expect(find.text('@ThreadAgent'), findsNothing);
          await tester.enterText(fieldFor(controllers.first), '');
          await tester.enterText(fieldFor(controllers.last), '@');
          await tester.pumpAndSettle();
          expect(find.text('@Coordinator'), findsOneWidget);
          expect(
            find.text('@ThreadAgent'),
            root == 'unassigned' ? findsNothing : findsOneWidget,
          );
          expect(find.text('@Agent'), findsNothing);
          expect(find.text('@A12'), findsNothing);
          if (root != 'unassigned') {
            await tester.tap(find.text('@ThreadAgent'));
            await tester.pumpAndSettle();
            expect(controllers.last.text, '@ThreadAgent ');
            await tester.tap(find.byTooltip(RegExp(r'^Send message')).last);
            await tester.pumpAndSettle();
            final sent = requests.lastWhere(
              (request) =>
                  request['parent_id'] == root && request['body'] != null,
            );
            expect(sent['mentions'], [
              {
                'kind': 'agent',
                'id': root == 'root' ? 'assigned-id' : 'other-id',
                'label': 'ThreadAgent',
              },
            ]);
            expect(sent[direct ? 'recipient_pubkey' : 'channel_id'],
                direct ? 'bob' : 'engineering');
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
