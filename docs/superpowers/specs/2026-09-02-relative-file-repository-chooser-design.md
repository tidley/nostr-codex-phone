# Relative File Repository Chooser

## Goal

Let a user open a relative repository file path that is not available in the
current conversation worktree. The selection applies to that request only.

## Flow

1. The user taps a linked relative path in a workspace message.
2. The client first reads it from the conversation worktree.
3. If that read reports a missing path, the client opens a repository chooser.
4. The chooser loads repositories from the active worker and lists Git
   repositories only. It includes search, loading, empty, and cancel states.
5. The user selects a repository. The client sends one `read_file` request for
   the selected repository root plus the original relative path.
6. The existing Files panel displays the result or its read error.

## Boundaries

- A choice does not change the conversation folder scope or repository target.
- The chooser does not probe multiple repositories or guess a match.
- Cancelling does not open the Files panel or persist a selection.
- The chooser uses the existing `RepoChoice` data and worker folder-loading
  request path.

## Verification

- A path available in the conversation worktree opens directly.
- A missing path opens the chooser after the initial read error.
- Selecting a repository requests the file beneath that repository only.
- Cancelling leaves the current conversation and Files state unchanged.
- The selected repository is not retained when another file link is opened.
