---
name: git_push
description: Git add, commit and push
disable-model-invocation: true
---

## Git add, commit, and push

Use a deliberate staging flow. **Do not use `git add .`** — it stages every untracked file in the tree (including editor artifacts and local plugin state).

1. Review: `git status` and `git diff` (and `git diff --staged` after staging).
2. Stage tracked edits and removals: `git add -u` (from repo root, or with pathspecs).
3. Stage **new** files explicitly: `git add path/to/file …` only for paths that belong in the repo.
4. Commit and push:

```bash
git commit -m "your commit message" && git push
```

If the working tree only has modifications to tracked files, a common sequence is:

```bash
git add -u && git commit -m "your commit message" && git push
```

When adding new files, run `git add` on those paths **before** `git commit`.
