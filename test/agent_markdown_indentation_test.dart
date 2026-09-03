import 'package:crew/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes a shared four-space prefix from agent Markdown', () {
    expect(
      normalizeAgentMarkdownIndentation(
        '    # Result\n    Plain text\n\n    - item',
      ),
      '# Result\nPlain text\n\n- item',
    );
  });

  test('removes the prefix from whitespace-only lines outside code fences', () {
    expect(
      normalizeAgentMarkdownIndentation('    First\n    \n    Last'),
      'First\n\nLast',
    );
  });

  test('removes a shared tab prefix from agent Markdown', () {
    expect(
      normalizeAgentMarkdownIndentation('\t# Result\n\tPlain text'),
      '# Result\nPlain text',
    );
  });

  test('preserves fenced code blocks byte-for-byte', () {
    expect(
      normalizeAgentMarkdownIndentation(
        '    Before\n```dart\n    final code = 1;\n```\n    After',
      ),
      'Before\n```dart\n    final code = 1;\n```\nAfter',
    );
  });

  test('keeps nested list indentation without a universal prefix', () {
    const markdown = 'Introduction\n    - nested item\n      continuation';

    expect(normalizeAgentMarkdownIndentation(markdown), markdown);
  });

  test('keeps block quote indentation without a universal prefix', () {
    const markdown = 'Summary\n    > quoted detail\n    > another detail';

    expect(normalizeAgentMarkdownIndentation(markdown), markdown);
  });

  test('keeps a fenced block when no text exists outside it', () {
    const markdown = '```dart\n    final code = 1;\n```';

    expect(normalizeAgentMarkdownIndentation(markdown), markdown);
  });
}
