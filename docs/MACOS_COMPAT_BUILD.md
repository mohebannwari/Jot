# Legacy macOS Test Builds — Recipe

How to produce a Debug `.app` of Jot that runs on a **previous macOS version** (e.g. macOS 14) for compatibility testing on a second Mac, zipped and dropped on the user's Desktop.

Use this recipe whenever the user says something like:

- "zip up a build for my macOS 14 Mac"
- "recompile a runtime for macOS `<N>` so I can test it"
- "give me a test build for the old Mac"

---

## The floor

The project's `MACOSX_DEPLOYMENT_TARGET` for the `Jot` target is **`14.0`** (`Jot.xcodeproj/project.pbxproj`, lines ~350 and ~409). Anything at or above that works with this recipe as-is. Anything **below** 14.0 requires lowering the deployment target in the pbxproj first — not a pure package-and-ship operation. Flag that back to the user before touching it.

The `ShareExtension` target has a higher floor (`26.2`). It still gets embedded into `Jot.app` because it's an embedded-content dependency of the main target, but it simply won't register on older macOS — the host app launches fine. Do not "fix" this by deleting the `.appex` or changing the extension's deployment target; that's not a real problem.

---

## Why this recipe exists

Jot's primary development target is macOS 26 (Liquid Glass, FoundationModels, etc.). All 26-only APIs must be behind `#available` or `#if canImport` guards, and the only way to verify those guards hold is to actually run the app on the older OS. The user has a second Apple Silicon Mac for this.

Three failure modes the recipe avoids:

1. **Building the full `Jot` scheme fails** — the scheme pulls in targets that may trip; `-target Jot` sidesteps scheme aggregation.
2. **`zip` breaks the code signature** — `zip` strips resource forks on some macOS versions, which invalidates the signature inside `_CodeSignature/`. `ditto` preserves everything the signature depends on.
3. **The first launch on the target Mac is blocked by Gatekeeper** — ad-hoc signed apps carry the `com.apple.quarantine` xattr after unzip. Clearing it is a one-line fix on the target machine.

---

## Recipe

### 1. Build

From the repo root:

```bash
xcodebuild -project Jot.xcodeproj -target Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -40
```

- `-target Jot` (not `-scheme Jot`) — targets the main app directly and skips scheme-level aggregation.
- Wait for `** BUILD SUCCEEDED **`. The artifact lands at `build/Debug/Jot.app` (xcodebuild's default `SYMROOT` is `./build/` when run from the project directory).
- If the build takes more than ~30s, run it in the background and poll the output file rather than blocking the main context.

### 2. Re-sign ad-hoc, deep

```bash
cd build/Debug
codesign --force --deep --sign - Jot.app
```

- `--sign -` = ad-hoc (no identity, no provisioning profile). Xcode's original signature is tied to your Apple Development identity and a specific provisioning profile — that's fine locally but makes Gatekeeper more finicky on a second Mac. Ad-hoc side-steps that.
- `--deep` walks embedded bundles. Required because `Jot.app/Contents/PlugIns/ShareExtension.appex` is embedded and needs to be re-signed to match the host.
- `--force` replaces the existing signature in place.

### 3. Package with `ditto`

```bash
ditto -c -k --sequesterRsrc --keepParent Jot.app ~/Desktop/Jot-macOS<N>-Debug.zip
```

- `-c -k` — create a PKZip archive.
- `--sequesterRsrc` — preserves resource forks and extended attributes in a signature-compatible way.
- `--keepParent` — the archive contains `Jot.app/…` at the top level (not flattened contents).
- Name the output with the target macOS version so past zips don't get confused. For macOS 14: `~/Desktop/Jot-macOS14-Debug.zip`.

**Never use `zip`** for this. It strips resource forks on some macOS versions and breaks the code signature.

### 4. Tell the user what to do on the target Mac

After unzipping on the macOS `<N>` machine, the user runs:

```bash
xattr -cr Jot.app
```

Then right-click → **Open** (first launch only). After the first launch, the app opens normally via Finder.

`xattr -cr` clears the `com.apple.quarantine` xattr that AirDrop / Safari / unzip add, which is what normally triggers the "Apple cannot check it for malicious software" dialog for ad-hoc signed binaries. It's required; double-clicking alone will fail.

---

## One-liner (for when the user just wants the thing)

```bash
cd /Users/mohebanwari/development/Jot && \
  xcodebuild -project Jot.xcodeproj -target Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -8 && \
  cd build/Debug && \
  codesign --force --deep --sign - Jot.app && \
  ditto -c -k --sequesterRsrc --keepParent Jot.app ~/Desktop/Jot-macOS14-Debug.zip && \
  ls -lh ~/Desktop/Jot-macOS14-Debug.zip
```

Swap `macOS14` in the filename for whatever version was requested.

---

## Checklist before declaring done

- [ ] `** BUILD SUCCEEDED **` appears in the build log.
- [ ] `codesign` output says `replacing existing signature` (or is silent — no errors).
- [ ] `ls -lh ~/Desktop/Jot-macOS<N>-Debug.zip` shows a file roughly 30–50 MB.
- [ ] The user was told to run `xattr -cr Jot.app` on the target Mac before first launch.

---

## Do not do

- Do not run the app locally to "verify" it (rule: no unsolicited launches — see _Prohibited_).
- Do not `pkill` / `killall` Jot, `open` the built `.app`, or `touch` the bundle. The user handles relaunches via the in-app update panel on their primary Mac.
- Do not use plain `zip` instead of `ditto`.
- Do not delete or modify `ShareExtension.appex` to "fix" its deployment-target mismatch — it's expected and harmless on older macOS.
- Do not lower the project `MACOSX_DEPLOYMENT_TARGET` without explicit user approval if they request a build for macOS below 14.0.

---

## Related

- Global project memory: `~/.claude/projects/-Users-mohebanwari-development-Jot/memory/project_macos14_compat.md`
- Build policy (when to run builds at all): `AGENTS.md` → **Build & Launch** section
- No-relaunch-after-build policy: `AGENTS.md` → **Build & Launch → After any build**
