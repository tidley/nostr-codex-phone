# Relative File Repository Chooser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user select a temporary active-worker repository when a linked relative file is absent from the conversation worktree.

**Architecture:** Keep relative-file links on their existing direct-read path. Add a result callback to workspace file reads so the workspace UI can distinguish a missing file from a successful or other failed request. For missing files, open a repository-only picker backed by existing `RepoChoice` loading; a selected absolute repository root is combined with the original relative path for one follow-up read.

**Tech Stack:** Flutter, Dart, existing Nostr tool requests, existing `RepoChoice` repository discovery.

---

### Task 1: Preserve Absolute Repository Paths

**Files:**
- Modify: `lib/main.dart:6905-6911`
- Test: `test/file_browser_path_test.dart`

- [ ] **Step 1: Write the failing path-composition tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:crew/main.dart' show fileBrowserPath;

void main() {
  test('joins a relative file to a relative browser directory', () {
    expect(fileBrowserPath('docs', 'guide.md'), 'docs/guide.md');
  });

  test('preserves an absolute repository directory', () {
    expect(
      fileBrowserPath('/home/worker/code/project', 'docs/guide.md'),
      '/home/worker/code/project/docs/guide.md',
    );
  });
}
```

- [ ] **Step 2: Run the test to verify the absolute-path case fails**

Run: `flutter test test/file_browser_path_test.dart`

Expected: FAIL because `fileBrowserPath` is not exposed and the existing helper removes the leading slash from the directory.

- [ ] **Step 3: Extract the path helper and retain absolute directories**

Move `_fileBrowserPath` to a top-level `fileBrowserPath` function in `lib/main.dart`. Keep an absolute requested file unchanged. Strip only trailing slashes from a directory; when that directory starts with `/`, join it directly to the cleaned child path. For relative directories, retain the existing normalized relative result. Update all `_fileBrowserPath` call sites to use `fileBrowserPath`.

```dart
String fileBrowserPath(String directory, String path) {
  final rawPath = path.trim();
  if (rawPath.startsWith('/')) return rawPath;
  final base = directory.trim().replaceFirst(RegExp(r'/+$'), '');
  final child = rawPath.replaceFirst(RegExp(r'^/+'), '');
  if (base.isEmpty) return child;
  return '$base/$child';
}
```

- [ ] **Step 4: Run the path tests**

Run: `flutter test test/file_browser_path_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the path helper**

```bash
git add lib/main.dart test/file_browser_path_test.dart
```

### Task 2: Return Workspace File Results to the Caller

**Files:**
- Modify: `lib/main.dart:6067-6102, 8620-8627`
- Modify: `lib/src/main_widgets.dart:1092-1097, 3399-3416`
- Test: `test/file_browser_path_test.dart`

- [ ] **Step 1: Add a failing callback test**

Add a testable top-level predicate in `lib/main.dart` that identifies a missing-file result without treating every read error as a missing file.

```dart
test('identifies a missing file result', () {
  expect(isMissingFileError('Could not read `docs/guide.md`: No such file or directory'), isTrue);
  expect(isMissingFileError('Refusing to read outside `/repo`.'), isFalse);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/file_browser_path_test.dart`

Expected: FAIL because `isMissingFileError` does not exist.

- [ ] **Step 3: Implement the narrow missing-file predicate**

Add `isMissingFileError(String? error)` in `lib/main.dart`. It must return true only for a nonempty error containing `No such file or directory`.

```dart
bool isMissingFileError(String? error) =>
    error?.contains('No such file or directory') == true;
```

- [ ] **Step 4: Extend workspace file reads with a result callback**

Change `_TeamWorkspace.onReadWorkspaceFile` to accept an optional named `onResult` callback of `ValueChanged<FileContentResult>`. In the `lib/main.dart` callback, pass `_sendToolRequest` an `onResult` handler that converts `ToolResultPayload` with `FileContentResult.fromPayload` and invokes the supplied callback. Keep the existing workspace preview update when no callback was supplied.

```dart
final Future<void> Function(
  String conversationKey,
  String directory,
  String path, {
  ValueChanged<FileContentResult>? onResult,
}) onReadWorkspaceFile;
```

- [ ] **Step 5: Run the path tests**

Run: `flutter test test/file_browser_path_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the result callback**

```bash
git add lib/main.dart lib/src/main_widgets.dart test/file_browser_path_test.dart
```

### Task 3: Add the Temporary Repository Chooser

**Files:**
- Modify: `lib/src/main_widgets.dart:3399-3416, 20273-20534`
- Test: `test/file_browser_path_test.dart`

- [ ] **Step 1: Add a repository-filter test**

Add a testable top-level helper that retains only Git repositories from `RepoChoice` values.

```dart
test('filters non-repositories from the chooser', () {
  final choices = [
    const RepoChoice(name: 'app', path: '/code/app', relativePath: 'app', isGitRepo: true),
    const RepoChoice(name: 'notes', path: '/code/notes', relativePath: 'notes', isGitRepo: false),
  ];

  expect(repositoryChoices(choices).map((choice) => choice.name), ['app']);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/file_browser_path_test.dart`

Expected: FAIL because `repositoryChoices` does not exist.

- [ ] **Step 3: Build a repository-only picker page**

Add `_RepositoryFileChooserPage` beside `_WorkingFolderPickerPage`. It accepts the clicked `relativePath`, `initialChoices`, and `onLoadFolders`. On initialization it loads active-worker choices, filters them with `repositoryChoices`, and supports case-insensitive search over `displayName` and `path`. Each row shows the Git icon, display name, and absolute path. Tapping a row pops its `RepoChoice`; the app bar close button returns null. Show a progress indicator while loading, `No repositories found` when the filtered list is empty, and a snackbar when loading fails.

- [ ] **Step 4: Open the chooser only after a missing direct read**

In the `onOpenRepositoryFile` handler, capture the active `conversationKey` and original path, then request the current-worktree read with `onResult`. Ignore a callback when that conversation is no longer focused. For a successful result, set `_workspaceFilePreview` and open Files. For a non-missing error, show that error in Files. For `isMissingFileError`, push `_RepositoryFileChooserPage`; do not set `_filesSelected` before the user chooses. If the user cancels, return without changing panel state. If a repository is chosen, call `onReadWorkspaceFile` once with `directory: choice.path` and the original path; set the Files panel only when that response arrives.

- [ ] **Step 5: Run the focused tests**

Run: `flutter test test/file_browser_path_test.dart`

Expected: PASS.

- [ ] **Step 6: Run static analysis and the existing workspace model tests**

Run: `flutter analyze lib/main.dart lib/src/main_widgets.dart && flutter test test/workspace_models_test.dart`

Expected: No analyzer findings and passing tests.

- [ ] **Step 7: Manually verify the UI flow**

1. Tap a file link that exists in the conversation worktree; confirm it opens directly.
2. Tap a missing relative file link; confirm the repository chooser opens without showing Files.
3. Search and select a Git repository; confirm the file opens from that repository.
4. Cancel the chooser; confirm the thread and Files state are unchanged.
5. Open a second relative file link; confirm no earlier repository selection is prefilled or retained.

- [ ] **Step 8: Commit the chooser**

```bash
git add lib/src/main_widgets.dart test/file_browser_path_test.dart
```
