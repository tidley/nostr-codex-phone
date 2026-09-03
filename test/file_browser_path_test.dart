import 'package:crew/main.dart'
    show
        fileBrowserPath,
        isMissingFileError,
        repoListRequestId,
        workspaceActionWorkdir;
import 'package:crew/src/repo_choice.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('identifies a missing file error', () {
    expect(
      isMissingFileError(
        'Could not read `docs/guide.md`: No such file or directory',
      ),
      isTrue,
    );
    expect(isMissingFileError('Refusing to read outside `/repo`.'), isFalse);
  });

  test('uses the selected repository for workspace file and Git actions', () {
    const repository = RepoChoice(
      name: 'app',
      path: '/home/worker/code/app',
      relativePath: 'app',
      isGitRepo: true,
    );

    expect(
      workspaceActionWorkdir(repository, '/home/worker/code/default'),
      repository.path,
    );
  });

  test('reads a non-empty repository list request ID', () {
    expect(
      repoListRequestId('{"repo_list":{"request_id":"repo-1","roots":[]}}'),
      'repo-1',
    );
    expect(repoListRequestId('{"repo_list":{"roots":[]}}'), isNull);
  });
}
