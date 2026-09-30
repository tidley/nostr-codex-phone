import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crew/main.dart';
import 'package:crew/src/workspace_models.dart';

void main() {
  testWidgets('workspace board shows a blocked task and admin retry control', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceBoard(
            tasks: [
              WorkspaceBoardTask(
                id: 'task-1',
                title: 'Review release notes',
                conversationKey: 'engineering',
                instruction: 'Review the release notes.',
                folderScope: const [],
                schedule: 'once',
                state: 'blocked',
                createdBy: 'owner',
                createdAt: 10,
                updatedAt: 20,
              ),
            ],
            timelineEntries: const [
              WorkspaceBoardTimelineEntry(
                id: 'entry-1',
                taskId: 'task-1',
                state: 'blocked',
                detail: 'Worker stopped',
                createdAt: 20,
              ),
            ],
            isAdmin: true,
            conversationLabel: (key) => '# $key',
            onCreate: () async {},
            onEdit: (_) async {},
            onRetry: (_) async => retried = true,
            onCancel: (_) async {},
            onMoveToScheduled: (_) async {},
            onMove: (_, _) async {},
            onOpenTaskThread: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Review release notes'), findsOneWidget);
    expect(find.text('# engineering'), findsOneWidget);
    expect(find.text('Worker stopped'), findsOneWidget);
    await tester.ensureVisible(find.text('Review release notes'));
    await tester.tap(find.text('Review release notes'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Move to scheduled'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('workspace board keeps mutation controls from members', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceBoard(
            tasks: [
              WorkspaceBoardTask(
                id: 'task-1',
                title: 'Review release notes',
                conversationKey: 'engineering',
                instruction: 'Review the release notes.',
                folderScope: const [],
                schedule: 'once',
                state: 'blocked',
                createdBy: 'owner',
                createdAt: 10,
                updatedAt: 20,
              ),
            ],
            timelineEntries: const [],
            isAdmin: false,
            conversationLabel: (key) => '# $key',
            onCreate: () async {},
            onEdit: (_) async {},
            onRetry: (_) async {},
            onCancel: (_) async {},
            onMoveToScheduled: (_) async {},
            onMove: (_, _) async {},
            onOpenTaskThread: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('New task'), findsNothing);
    await tester.ensureVisible(find.text('Review release notes'));
    await tester.tap(find.text('Review release notes'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('workspace board keeps six ordered workflow lanes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final columns = [
      ('backlog', 'Backlog'),
      ('ready', 'Ready'),
      ('progress', 'In Progress'),
      ('review', 'Review'),
      ('done', 'Done'),
    ]
        .map(
          (column) => WorkspaceBoardColumn.fromJson({
            'id': column.$1,
            'name': column.$2,
            'rank': 1024,
          }),
        )
        .toList();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceBoard(
            tasks: [
              WorkspaceBoardTask(
                id: 'task-1',
                title: 'Build release',
                conversationKey: 'engineering',
                instruction: 'Build the release.',
                folderScope: const [],
                schedule: 'once',
                state: 'scheduled',
                boardColumn: '',
                createdBy: 'owner',
                createdAt: 10,
                updatedAt: 20,
              ),
            ],
            columns: columns,
            timelineEntries: const [],
            isAdmin: true,
            conversationLabel: (key) => '# $key',
            onCreate: () async {},
            onEdit: (_) async {},
            onRetry: (_) async {},
            onCancel: (_) async {},
            onMoveToScheduled: (_) async {},
            onMove: (_, _) async {},
            onOpenTaskThread: (_) {},
          ),
        ),
      ),
    );

    final laneHeaders = [
      'Backlog',
      'Scheduled',
      'In Progress',
      'Review',
      'Blocked',
      'Done',
    ];
    for (final label in laneHeaders) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['Queued', 'Running', 'Integrating']) {
      expect(find.text(label), findsNothing);
    }
    final positions = laneHeaders
        .map((label) => tester.getRect(find.text(label)).left)
        .toList();
    for (var index = 1; index < positions.length; index++) {
      expect(positions[index], greaterThan(positions[index - 1]));
    }
  });

  testWidgets('workspace board opens the linked task thread from details', (
    tester,
  ) async {
    WorkspaceBoardTask? opened;
    final task = WorkspaceBoardTask(
      id: 'task-1',
      title: 'Review release notes',
      conversationKey: 'engineering',
      instruction: 'Review the release notes.',
      folderScope: const [],
      schedule: 'once',
      state: 'scheduled',
      createdBy: 'owner',
      createdAt: 10,
      updatedAt: 20,
      rootMessageId: 'thread-1',
      agentId: 'agent-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceBoard(
            tasks: [task],
            timelineEntries: const [],
            isAdmin: false,
            conversationLabel: (_) => '# engineering',
            onCreate: () async {},
            onEdit: (_) async {},
            onRetry: (_) async {},
            onCancel: (_) async {},
            onMoveToScheduled: (_) async {},
            onMove: (_, _) async {},
            onOpenTaskThread: (value) => opened = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review release notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('# engineering').last);
    expect(opened?.rootMessageId, 'thread-1');
  });

  testWidgets('workspace board sends the target column after a task drop', (
    tester,
  ) async {
    WorkspaceBoardTask? moved;
    String? targetColumn;
    await tester.binding.setSurfaceSize(const Size(1800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceBoard(
            tasks: [
              WorkspaceBoardTask(
                id: 'task-1',
                title: 'Review release notes',
                conversationKey: 'engineering',
                instruction: 'Review the release notes.',
                folderScope: const [],
                schedule: 'once',
                state: 'scheduled',
                createdBy: 'owner',
                createdAt: 10,
                updatedAt: 20,
              ),
            ],
            timelineEntries: const [],
            isAdmin: true,
            conversationLabel: (key) => '# $key',
            onCreate: () async {},
            onEdit: (_) async {},
            onRetry: (_) async {},
            onCancel: (_) async {},
            onMoveToScheduled: (_) async {},
            onMove: (task, column) async {
              moved = task;
              targetColumn = column;
            },
            onOpenTaskThread: (_) {},
          ),
        ),
      ),
    );

    await tester.drag(find.text('Review release notes'), const Offset(1120, 0));
    await tester.pumpAndSettle();

    expect(moved?.id, 'task-1');
    expect(targetColumn, 'done');
  });

  testWidgets(
    'board task editor sends its scoped create request to the workspace transport',
    (tester) async {
      Map<String, Object?>? request;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showWorkspaceBoardTaskEditor(
                context: context,
                title: 'Review release notes',
                conversationKey: 'channel:engineering',
                folderScope: const ['/work/phone'],
                conversationOptions: const {
                  'channel:engineering': '# engineering',
                },
                onRequest: (value) async => request = value,
              ),
              child: const Text('New task'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(1),
        'Check all blockers.',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final savedRequest = request!;
      expect(savedRequest['action'], 'create_board_task');
      expect(savedRequest['board_task'], {
        'title': 'Review release notes',
        'conversation_key': 'channel:engineering',
        'instruction': 'Check all blockers.',
        'folder_scope': ['/work/phone'],
        'schedule': 'once',
        'next_run_at': isA<int>(),
      });
    },
  );

  testWidgets(
    'board task editor keeps a thread action prefilled and instruction blank',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showWorkspaceBoardTaskEditor(
                context: context,
                title: 'Release readiness',
                conversationKey: 'channel:engineering',
                folderScope: const ['/work/phone'],
                conversationOptions: const {
                  'channel:engineering': '# engineering',
                },
                onRequest: (_) async {},
              ),
              child: const Text('Create board task'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Create board task'));
      await tester.pumpAndSettle();

      expect(find.text('Release readiness'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '',
      );
      expect(find.text('Scope: /work/phone'), findsOneWidget);
    },
  );

}
