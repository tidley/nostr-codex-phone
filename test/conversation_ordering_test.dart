import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_codex_phone/src/conversation_message.dart';
import 'package:nostr_codex_phone/src/incoming_route.dart';
import 'package:nostr_codex_phone/src/repo_target.dart';
import 'package:nostr_codex_phone/src/repo_target_merge.dart';

void main() {
  test('matches target invites by workdir before pubkey', () {
    final targets = [
      const RepoTargetMergeIdentity(
        id: 'phone',
        pubkey: 'npub1phone',
        workdir: '/home/tom/code/phone',
      ),
      const RepoTargetMergeIdentity(
        id: 'monitor',
        pubkey: 'npub1oldmonitor',
        workdir: '/home/tom/code/pave/monitor',
      ),
      const RepoTargetMergeIdentity(
        id: 'bcm',
        pubkey: 'npub1oldbcm',
        workdir: '/home/tom/code/pave/bcm_app',
      ),
    ];

    final incomingRestartedBcm = const RepoTargetMergeIdentity(
      id: 'invite-new-id',
      pubkey: 'npub1newbcm',
      workdir: '/home/tom/code/pave/bcm_app',
    );

    expect(repoTargetMergeIndex(targets, incomingRestartedBcm), 2);
  });

  test('falls back to pubkey when target has no workdir', () {
    final targets = [
      const RepoTargetMergeIdentity(id: 'saved', pubkey: 'npub1same'),
    ];

    final incoming = const RepoTargetMergeIdentity(
      id: 'invite-new-id',
      pubkey: 'npub1same',
    );

    expect(repoTargetMergeIndex(targets, incoming), 0);
  });

  test('does not merge routed sessions by shared service pubkey', () {
    final targets = [
      const RepoTargetMergeIdentity(
        id: 'phone',
        pubkey: 'npub1service',
        workdir: '/home/tom/code/phone',
      ),
    ];

    final incoming = const RepoTargetMergeIdentity(
      id: 'invite-new-id',
      pubkey: 'npub1service',
      workdir: '/home/tom/code/pave/monitor',
    );

    expect(repoTargetMergeIndex(targets, incoming), -1);
  });

  test(
    'routes incoming responses by embedded workdir before shared pubkey',
    () {
      final targets = [
        const RepoTarget(
          id: 'phone',
          name: 'phone',
          pubkey: 'npub1service',
          relays: ['wss://relay.example'],
          workdir: '/home/tom/code/phone',
        ),
        const RepoTarget(
          id: 'monitor',
          name: 'monitor',
          pubkey: 'npub1service',
          relays: ['wss://relay.example'],
          workdir: '/home/tom/code/pave/monitor',
        ),
      ];

      expect(
        conversationKeyForIncomingRoute(
          targets: targets,
          senderPubkey: 'npub1service',
          senderPubkeyHex: '',
          rawJson:
              '{"workdir":"/home/tom/code/pave/monitor","response":"done"}',
        ),
        'monitor',
      );
    },
  );

  test(
    'routes incoming transcripts by embedded workdir before shared pubkey',
    () {
      final targets = [
        const RepoTarget(
          id: 'phone',
          name: 'phone',
          pubkey: 'npub1service',
          relays: ['wss://relay.example'],
          workdir: '/home/tom/code/phone',
        ),
        const RepoTarget(
          id: 'hybrid',
          name: 'hybrid',
          pubkey: 'npub1service',
          relays: ['wss://relay.example'],
          workdir: '/home/tom/code/chapar-stun-hybrid',
        ),
      ];

      expect(
        conversationKeyForIncomingRoute(
          targets: targets,
          senderPubkey: 'npub1service',
          senderPubkeyHex: '',
          rawJson:
              '{"workdir":"/home/tom/code/chapar-stun-hybrid","transcript":"Hi"}',
        ),
        'hybrid',
      );
    },
  );

  test('drops ambiguous unrouted responses from shared service pubkey', () {
    final targets = [
      const RepoTarget(
        id: 'phone',
        name: 'phone',
        pubkey: 'npub1service',
        relays: ['wss://relay.example'],
        workdir: '/home/tom/code/phone',
      ),
      const RepoTarget(
        id: 'monitor',
        name: 'monitor',
        pubkey: 'npub1service',
        relays: ['wss://relay.example'],
        workdir: '/home/tom/code/pave/monitor',
      ),
    ];

    expect(
      conversationKeyForIncomingRoute(
        targets: targets,
        senderPubkey: 'npub1service',
        senderPubkeyHex: '',
        rawJson: '{"response":"old"}',
      ),
      isNull,
    );
  });

  test('routes unrouted transcript to matching pending voice event', () {
    final messagesByTarget = {
      'phone': <ConversationMessage>[],
      'hybrid': [
        ConversationMessage(
          direction: MessageDirection.outgoing,
          kind: 'transcribing',
          text: 'Transcribing...',
          eventId: 'voice-event',
          timestamp: DateTime(2026, 7, 1, 22, 30),
        ),
      ],
    };

    expect(
      conversationKeyForPendingTranscript(
        messagesByTarget: messagesByTarget,
        sourceEventId: 'voice-event',
      ),
      'hybrid',
    );
  });

  test('routes shared-pubkey response to the only pending session', () {
    final targets = [
      const RepoTarget(
        id: 'master',
        name: 'master',
        pubkey: 'npub1service',
        relays: ['wss://relay.example'],
        isMasterSession: true,
      ),
      const RepoTarget(
        id: 'phone',
        name: 'phone',
        pubkey: 'npub1service',
        relays: ['wss://relay.example'],
        workdir: '/home/tom/code/phone',
      ),
    ];
    final messagesByTarget = {
      'master': [
        ConversationMessage(
          direction: MessageDirection.incoming,
          kind: 'processing',
          text: '',
          eventId: 'pending-master',
          timestamp: DateTime(2026, 7),
        ),
      ],
      'phone': <ConversationMessage>[],
    };

    expect(
      conversationKeyForPendingResponse(
        targets: targets,
        messagesByTarget: messagesByTarget,
        senderPubkey: 'npub1service',
        senderPubkeyHex: '',
      ),
      'master',
    );
  });

  test('orders screenshot regression chronologically by timestamp', () {
    final base = DateTime(2026, 6, 23, 17, 25);
    final replyToEarlierPrompt = ConversationMessage(
      direction: MessageDirection.incoming,
      kind: 'response',
      text: 'Yes: /home/tom/code/pave/monitor',
      eventId: 'reply-earlier',
      timestamp: base,
    );
    final newerPrompt = ConversationMessage(
      direction: MessageDirection.outgoing,
      kind: 'query',
      text: "What's the latest of the status with the reports?",
      eventId: 'newer-prompt',
      timestamp: base.add(const Duration(minutes: 1)),
    );
    final transcribing = ConversationMessage(
      direction: MessageDirection.outgoing,
      kind: 'transcribing',
      text: 'Transcribing...',
      eventId: 'media-pending',
      timestamp: base.add(const Duration(minutes: 1, seconds: 12)),
    );

    final ordered = sortConversationMessagesChronological([
      newerPrompt,
      replyToEarlierPrompt,
      transcribing,
    ]);

    expect(ordered, [replyToEarlierPrompt, newerPrompt, transcribing]);
  });

  test('keeps stale outgoing transcribing placeholders at the bottom', () {
    final base = DateTime(2026, 6, 23, 17, 25);
    final staleTranscribing = ConversationMessage(
      direction: MessageDirection.outgoing,
      kind: 'transcribing',
      text: 'Transcribing...',
      eventId: 'stale-transcribing',
      timestamp: base,
    );
    final lastReceived = ConversationMessage(
      direction: MessageDirection.incoming,
      kind: 'response',
      text: 'Last received message',
      eventId: 'last-received',
      timestamp: base.add(const Duration(minutes: 3)),
    );

    final ordered = sortConversationMessagesChronological([
      staleTranscribing,
      lastReceived,
    ]);

    expect(ordered, [lastReceived, staleTranscribing]);
  });

  test('applies deterministic tie breaks for same-timestamp messages', () {
    final timestamp = DateTime(2026, 6, 23, 17, 26);
    final messages = [
      ConversationMessage(
        direction: MessageDirection.incoming,
        kind: 'response',
        text: 'response',
        eventId: 'event-b',
        timestamp: timestamp,
      ),
      ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'media_bundle',
        text: 'media',
        eventId: 'event-a',
        timestamp: timestamp,
      ),
      ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'transcribing',
        text: 'Transcribing...',
        eventId: 'event-c',
        timestamp: timestamp,
      ),
    ];

    final ordered = sortConversationMessagesChronological(messages);

    expect(ordered.map((message) => message.eventId), [
      'event-a',
      'event-b',
      'event-c',
    ]);
  });

  test('keeps pending transcription placeholders at the bottom', () {
    final base = DateTime(2026, 6, 24, 16);
    final queuedVoice = ConversationMessage(
      direction: MessageDirection.outgoing,
      kind: 'transcribing',
      text: 'Queued',
      eventId: 'voice-pending',
      timestamp: base,
    );
    final receivedReply = ConversationMessage(
      direction: MessageDirection.incoming,
      kind: 'response',
      text: 'Previous reply arrived',
      eventId: 'reply',
      timestamp: base.add(const Duration(minutes: 2)),
    );
    final followUp = ConversationMessage(
      direction: MessageDirection.outgoing,
      kind: 'query',
      text: 'Follow up',
      eventId: 'follow-up',
      timestamp: base.add(const Duration(minutes: 3)),
    );

    final ordered = sortConversationMessagesChronological([
      followUp,
      queuedVoice,
      receivedReply,
    ]);

    expect(ordered, [receivedReply, followUp, queuedVoice]);
  });

  test('finds oldest active transcribing placeholder and ignores queued', () {
    final base = DateTime(2026, 7, 1, 22);
    final messages = [
      ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'transcribing',
        text: 'Queued',
        eventId: 'queued',
        timestamp: base,
      ),
      ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'transcribing',
        text: 'Transcribing...',
        eventId: 'newer-active',
        timestamp: base.add(const Duration(minutes: 2)),
      ),
      ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'transcribing',
        text: 'Transcribing message...',
        eventId: 'older-active',
        timestamp: base.add(const Duration(minutes: 1)),
      ),
    ];

    expect(oldestActiveTranscribingPlaceholderIndex(messages), 2);
  });

  test('orders completed voice transcript before its response', () {
    final base = DateTime(2026, 7, 1, 12);
    final transcript = ConversationMessage(
      direction: MessageDirection.outgoing,
      kind: 'transcript',
      text: 'Run the tests',
      eventId: 'voice-event',
      timestamp: base,
    );
    final response = ConversationMessage(
      direction: MessageDirection.incoming,
      kind: 'response',
      text: 'Tests passed',
      eventId: 'response-event',
      timestamp: base.add(const Duration(seconds: 12)),
    );

    final ordered = sortConversationMessagesChronological([
      response,
      transcript,
    ]);

    expect(ordered, [transcript, response]);
  });

  test('keeps shuffled npub traffic chronological during fuzz run', () {
    final random = Random(872341);
    final base = DateTime(2026, 6, 23, 17);
    final sessions = List.generate(12, (index) => _fakeNpub(index));
    final messagesBySession = <String, List<ConversationMessage>>{
      for (final session in sessions) session: <ConversationMessage>[],
    };
    final activeSessionsVisited = <String>{};

    for (var index = 0; index < 2500; index += 1) {
      final session = sessions[random.nextInt(sessions.length)];
      final direction = random.nextBool()
          ? MessageDirection.outgoing
          : MessageDirection.incoming;
      final kind = switch (random.nextInt(9)) {
        0 => 'query',
        1 => 'response',
        2 => 'transcribing',
        3 => 'processing',
        4 => 'media_bundle',
        5 => 'transcript',
        6 => 'audio_retry',
        7 => 'error',
        _ => 'invalid',
      };
      final timestamp = base.add(
        Duration(
          seconds: random.nextInt(3 * 60 * 60),
          milliseconds: index % 11 == 0 ? 0 : random.nextInt(1000),
        ),
      );

      messagesBySession[session]!.insert(
        random.nextInt(messagesBySession[session]!.length + 1),
        ConversationMessage(
          direction: direction,
          kind: kind,
          text: '$session $kind $index',
          eventId: 'event-${index % 200}-${random.nextInt(24)}',
          timestamp: timestamp,
        ),
      );

      if (index % 7 == 0) {
        final activeSession = sessions[random.nextInt(sessions.length)];
        activeSessionsVisited.add(activeSession);
        final ordered = sortConversationMessagesChronological(
          messagesBySession[activeSession]!,
        );
        _expectChronological(
          ordered,
          reason: 'session $activeSession is chronological after switch',
        );
      }
    }

    expect(activeSessionsVisited, containsAll(sessions));
    for (final entry in messagesBySession.entries) {
      final ordered = sortConversationMessagesChronological(entry.value);
      _expectChronological(
        ordered,
        reason: 'session ${entry.key} final ordering is chronological',
      );
    }
  });
}

String _fakeNpub(int index) {
  final alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final start = index % alphabet.length;
  final body = List.generate(
    59,
    (offset) => alphabet[(start + offset + index) % alphabet.length],
  ).join();
  return 'npub1$body';
}

void _expectChronological(
  List<ConversationMessage> ordered, {
  required String reason,
}) {
  for (var cursor = 1; cursor < ordered.length; cursor += 1) {
    expect(
      compareConversationMessagesChronological(
        ordered[cursor - 1],
        ordered[cursor],
      ),
      lessThanOrEqualTo(0),
      reason: reason,
    );
  }
}
