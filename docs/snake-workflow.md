# Snake workflow permissions

The workflow defaults to `permissions: {}`. Generation has no repository permissions and runs on a separate hosted runner. Platane/snk still receives the automatic job token through its default input for the contribution API, but that token has no repository content permission. The only artifact passed to publication is `snake-svg`, containing the two named SVG files. Upload/download use Actions artifact service credentials; they do not require repository `actions: write` or `contents: read` for this same-run transfer.

Publication requires successful generation and `refs/heads/main`. Only this job receives `contents: write`. It downloads the same run's named artifact, checks exactly two nonempty regular files, and copies only those filenames. It does not check out or run generation code, repository scripts, or artifact content. Git hooks are disabled. Git authentication exists only in the publication step environment and is not stored in Git config or remote URLs. All three Actions use reviewed 40-character commit SHAs resolved from their official repositories.

Existing `output` ancestry and unrelated files are retained. A missing branch receives an initial commit. Unchanged SVGs cause no commit. Push is a normal fast-forward push, so an outside concurrent writer causes failure instead of overwritten history. `snake-output` concurrency serializes running workflows without cancelling the active run. GitHub may replace pending runs and does not guarantee run ordering; this is not a FIFO queue.

`GITHUB_TOKEN` permissions apply to the repository, not a branch. The script targets `output`, but `contents: write` technically permits other repository content changes subject to existing repository protections. A compromised publication Action, runner, or workflow could misuse that permission. SHA pins reduce upstream tag drift but do not establish that dependencies are free from vulnerabilities. SVGs are treated as data for publication; this does not sanitize their browser content. Generation failure, artifact failure, or non-fast-forward publication requires inspection before rerunning.

No credentials, repository rulesets, default permissions, or other profile workflows are changed. Production generation/publication and merge remain unexecuted for this PR. Local checks are:

```sh
ruby scripts/check_snake_workflow.rb
ruby tests/test_snake_workflow.rb
ruby tests/test_snake_publication.rb
actionlint .github/workflows/snake.yml
```

Publication fixtures run the actual inline shell against temporary local Git repositories. They verify history and unrelated-file preservation, first publication, no-op behavior, unexpected artifact rejection, external writer conflict, and absence of persisted authentication. Static fixtures reject permissions, triggers, destination, artifact, Action, and publication script changes. The script digest deliberately requires a fresh review when publication logic changes.

References: [GitHub token authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token), [concurrency semantics](https://docs.github.com/en/actions/using-jobs/using-concurrency), [upload-artifact](https://github.com/actions/upload-artifact/tree/ea165f8d65b6e75b540449e92b4886f43607fa02), [download-artifact](https://github.com/actions/download-artifact/tree/d3f86a106a0bac45b974a628896c90dbdf5c8093).
