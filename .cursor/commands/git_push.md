## Git add, commit, and push

Use a deliberate staging flow. **Do not use `git add .`** — it stages every untracked file in the tree (including editor artifacts and local plugin state).

1. Review: `git status` and `git diff` (and `git diff --staged` after staging).
2. Stage tracked edits and removals only: `git add -u` (from repo root, or pass pathspecs).
3. Stage **new** files explicitly: `git add path/to/file …` (only paths you intend to ship).
4. Commit and push:

```bash
git commit -m "your commit message" && git push
```

If you already staged everything you need, the commit line above is enough. Combine steps only after you are sure the index matches what you want:

```bash
git add -u && git commit -m "your commit message" && git push
```

Remember to `git add <new-files>` before commit when the change includes untracked paths you want in the repo.
