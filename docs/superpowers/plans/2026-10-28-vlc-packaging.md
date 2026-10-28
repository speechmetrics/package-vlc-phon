# VLC Packages for Phon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A GitHub Actions build that turns official VideoLAN 3.0.x releases into trimmed, smoke-tested `org.videolan:vlc-macos` and `org.videolan:vlc-windows-x64` zips and publishes them on tag.

**Architecture:** Small bash scripts do one job each (resolve version, fetch + verify, trim plug-ins, package per platform, verify Mac binaries), each covered by a plain-bash test file. A Maven-built Java program smoke-tests a package with vlcj. One workflow wires them together: package → smoke matrix → publish.

**Tech Stack:** bash, curl, shasum, unzip/zip, hdiutil, lipo, otool, install_name_tool, codesign (macOS), Java 21 + Maven + vlcj 4.11.0/4.12.1, ffmpeg (clip generation, local only), GitHub Actions, GitHub Packages (Maven).

**Spec:** `docs/superpowers/specs/2026-10-28-vlc-packaging-design.md`

**Tracking:** speechmetrics/package-vlc-phon#1. Update the issue with a summary after each phase.

## Global Constraints

- VLC 3.0.24; sources `https://get.videolan.org/vlc/<v>/macosx/vlc-<v>-universal.dmg` and `https://get.videolan.org/vlc/<v>/win64/vlc-<v>-win64.zip`, each with a `.sha256` file in `shasum -c` format (`<hash>  <filename>`).
- Mac zip layout: `VLC.app/Contents/MacOS/lib/{libvlc.dylib,libvlccore.dylib}`, `VLC.app/Contents/MacOS/plugins/*.dylib` (flat). No `__MACOSX/`, no `._*`, no symlinks.
- Windows zip layout: `VLC/{libvlc.dll,libvlccore.dll}`, `VLC/plugins/<category>/*.dll`. No `plugins.dat`, no `axvlc.dll`, no `npvlc.dll`.
- Both zips also carry VLC's licence and authors files under VLC's own names (`COPYING.txt`/`AUTHORS.txt` on Windows; the matching files from the DMG on Mac) and a `README.txt` naming the VLC version and linking `https://code.videolan.org/videolan/vlc/-/tree/<v>`. On Mac these sit in `VLC.app/Contents/MacOS/`, on Windows in `VLC/`.
- Every Mac Mach-O file in the package has both `arm64` and `x86_64`; references between VLC binaries use `@rpath/` or `@loader_path/` only.
- Tag `v<vlc>` or `v<vlc>-<n>`; Maven version = tag without `v`; VLC version = part before `-<n>`; must equal the `VLC_VERSION` file.
- Maven coordinates `org.videolan:vlc-macos:<version>:zip`, `org.videolan:vlc-windows-x64:<version>:zip`; repo URL `https://maven.pkg.github.com/speechmetrics/package-vlc-phon`; credentials `GITHUB_TOKEN`.
- Plug-in on neither keep nor remove list → kept, reported as `UNCLASSIFIED`. List entry absent from download → `WARNING`.
- Smoke test uses Phon's factory options `--no-metadata-network-access --no-plugins-cache` (plus `--aout=adummy` for runners), vlcj 4.11.0 and 4.12.1.
- Runners: `macos-15` (Apple silicon), `macos-15-intel` (Intel), `windows-latest`, `ubuntu-latest`.
- Commit messages: imperative subject ≤ 50 chars, blank line, body on the why, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work on a feature branch; PR into `main`.

## Review Focus

1. Tag that disagrees with `VLC_VERSION` (e.g. `v3.0.25` with file `3.0.24`) → build stops before downloading. Test in Task 2.
2. Corrupt or tampered download (checksum mismatch, 404) → script exits non-zero and leaves no partial output. Test in Task 3.
3. Symlinked or versioned dylibs in VLC's `lib/` (e.g. `libvlc.5.dylib` + `libvlc.dylib` link) → package holds real files with the unversioned names only. Test in Task 6.
4. Publish job re-run after one artifact already went up → skips the existing version instead of failing with 409. Covered in Task 8.
5. A new VLC release adding a plug-in → kept, listed as `UNCLASSIFIED` in log and Release notes, never deleted. Test in Task 1.

## File Structure

```
VLC_VERSION                     one line: 3.0.24
README.md                       what the repo does, how to bump VLC and release
lists/{macos,windows}-{keep,remove}.txt   plug-in lists (comments with #)
scripts/lib.sh                  shared: die(), read_list()
scripts/resolve-version.sh      tag → maven + vlc version
scripts/fetch.sh                download + sha256 verify
scripts/trim-plugins.sh         apply keep/remove lists, print report
scripts/package-windows.sh      win64.zip → vlc-windows-x64-<ver>.zip
scripts/package-macos.sh        dmg → vlc-macos-<ver>.zip
scripts/verify-macos.sh         universal + load-path check/fix
scripts/seed-lists.sh           one-off: draft lists from a VLC release
scripts/publish.sh              deploy one zip unless version exists
templates/README.txt            package README with @VLC_VERSION@
tests/run.sh                    runs every tests/test_*.sh
tests/helpers.sh                assert_eq, assert_file, assert_no_file, assert_fails
tests/test_*.sh                 one file per script
smoke/pom.xml, smoke/src/main/java/ca/phon/vlcsmoke/SmokeTest.java
smoke/allowed-errors.txt        regexes of tolerated VLC ERROR log lines
smoke/make-clips.sh, smoke/clips/*  generated test media (committed)
.github/workflows/build.yml
```

---

## Phase 1 — Packaging scripts

### Task 1: Test harness, list reader and plug-in trimming

**Files:**
- Create: `scripts/lib.sh`, `scripts/trim-plugins.sh`, `tests/run.sh`, `tests/helpers.sh`, `tests/test_trim.sh`, `README.md` (stub: purpose + "run `tests/run.sh`")

**Interfaces:**
- Produces: `read_list <file>` → prints non-blank entries, `#` comments and surrounding whitespace stripped. `die <msg>` → stderr + exit 1.
- Produces: `scripts/trim-plugins.sh --mode flat|category <plugins-dir> <keep-list> <remove-list>`. `flat`: entries are file names directly in `<plugins-dir>`. `category`: entries are subfolder names. Deletes removed entries; prints one line per item to stdout: `REMOVED <name>`, `KEPT <name>`, `UNCLASSIFIED <name>`, `WARNING missing <name>`; exit 0. Exit 1 if a name is on both lists.
- Produces: `tests/helpers.sh` functions `assert_eq <expected> <actual> <msg>`, `assert_file <path>`, `assert_no_file <path>`, `assert_fails <cmd...>`; `tests/run.sh` runs each `tests/test_*.sh`, prints PASS/FAIL per file and a final `N passed, M failed`, exits non-zero on any failure.

- [ ] **Step 1: Write failing tests** in `tests/test_trim.sh`, each building a fixture in `mktemp -d`:
  - `flat`: dir with `a.dylib b.dylib c.dylib new.dylib`, keep=`a.dylib`, remove=`b.dylib c.dylib gone.dylib` → `a.dylib`, `new.dylib` exist; `b`, `c` gone; output contains `REMOVED b.dylib`, `KEPT a.dylib`, `UNCLASSIFIED new.dylib`, `WARNING missing gone.dylib`.
  - `category`: dirs `codec/ gui/ lua/ newcat/` with one file each, keep=`codec`, remove=`gui lua` → `codec/`, `newcat/` remain, `UNCLASSIFIED newcat`.
  - comments/blank lines in lists are ignored (`# x`, `  codec  # trailing`).
  - name on both lists → `assert_fails`.
- [ ] **Step 2:** `tests/run.sh` → FAIL (script missing).
- [ ] **Step 3:** Implement `lib.sh`, `trim-plugins.sh`, `helpers.sh`, `run.sh` (`set -euo pipefail`, bash 3.2 compatible — macOS system bash).
- [ ] **Step 4:** `tests/run.sh` → `1 passed, 0 failed`.
- [ ] **Step 5:** Commit `Add plug-in trimming script with tests`.

### Task 2: Version resolution

**Files:** Create `VLC_VERSION` (`3.0.24`), `scripts/resolve-version.sh`, `tests/test_version.sh`

**Interfaces:**
- Produces: `scripts/resolve-version.sh [<git-ref-name>]` → prints two lines `MAVEN_VERSION=<v>` and `VLC_VERSION=<v>` (appendable to `$GITHUB_OUTPUT`). No argument or a non-tag ref → both equal `VLC_VERSION` file. Reads `VLC_VERSION` from the repo root (path overridable with env `VLC_VERSION_FILE` for tests).

- [ ] **Step 1: Failing tests:** `v3.0.24` → `3.0.24`/`3.0.24`; `v3.0.24-2` → `MAVEN_VERSION=3.0.24-2`, `VLC_VERSION=3.0.24`; no arg → `3.0.24`/`3.0.24`; `v3.0.25` with file `3.0.24` → fails; `3.0.24` (no `v`) and `vfoo` → fail.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement; tag regex `^v([0-9]+\.[0-9]+\.[0-9]+)(-[0-9]+)?$`.
- [ ] **Step 4:** Run → all pass.
- [ ] **Step 5:** Commit `Derive package version from release tag`.

### Task 3: Download with checksum check

**Files:** Create `scripts/fetch.sh`, `tests/test_fetch.sh`

**Interfaces:**
- Produces: `scripts/fetch.sh <url> <dest-dir>` → downloads `<url>` and `<url>.sha256` into `<dest-dir>`, verifies with `shasum -a 256 -c`, prints the downloaded file path. On any failure removes both files and exits 1. Skips the download if the file already exists and verifies.

- [ ] **Step 1: Failing tests** using `file://` URLs to fixtures in a temp dir: good file + matching `.sha256` → path printed, file present; wrong hash → fails, `assert_no_file` on both; missing `.sha256` → fails; missing file → fails.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement with `curl -fsSL --retry 3`.
- [ ] **Step 4:** Run → pass.
- [ ] **Step 5:** Commit `Verify VLC downloads against VideoLAN checksums`.

### Task 4: Seed the plug-in lists from VLC 3.0.24

**Files:** Create `scripts/seed-lists.sh`, `lists/macos-keep.txt`, `lists/macos-remove.txt`, `lists/windows-keep.txt`, `lists/windows-remove.txt`

**Interfaces:**
- Consumes: `fetch.sh`.
- Produces: the four committed lists. `scripts/seed-lists.sh <vlc-version> <out-dir>` (macOS only; one-off helper kept for future re-seeds) writes draft lists: Windows categories from folder names; each Mac plug-in placed in the category of the Windows plug-in with the same base name (`libfoo_plugin.dylib` ↔ `libfoo_plugin.dll`); Mac plug-ins with no Windows match written to `<out-dir>/macos-unmatched.txt` for hand placement.

Category decisions (from the spec):
- Keep: `access demux codec packetizer audio_output audio_filter audio_mixer video_output video_chroma video_filter stream_filter misc text_renderer spu meta_engine logger d3d9 d3d11`
- Remove: `gui control lua services_discovery stream_out access_output mux visualization keystore video_splitter stream_extractor`
- Mac-only by hand: `libmacosx_plugin` → remove; `libauhal_plugin`, `libvideotoolbox_plugin`, `libcaopengllayer_plugin` → keep; any other unmatched plug-in → placed by its VLC module category (`vlc --list` output or the module's source dir in VLC 3.0.24), with a comment naming the category.
- Non-universal Mac plug-ins are not listed; `package-macos.sh` removes them by rule (Task 6).

- [ ] **Step 1:** Implement `seed-lists.sh`; run `scripts/seed-lists.sh 3.0.24 build/seed`.
- [ ] **Step 2:** Hand-place every line of `macos-unmatched.txt`; copy drafts into `lists/` with a header comment per file and a `# <category>` comment above each group.
- [ ] **Step 3: Check:** every Windows category appears in exactly one Windows list; every 3.0.24 Mac plug-in (excluding non-universal ones) appears in exactly one Mac list — run `trim-plugins.sh` against copies of both downloads and confirm the report has zero `UNCLASSIFIED` and zero `WARNING`. Confirm `libvmem_plugin`, `libadummy_plugin`, `libpng_plugin` are in keep lists.
- [ ] **Step 4:** Commit `Add keep and remove lists for VLC plug-ins`.

### Task 5: Windows package

**Files:** Create `scripts/package-windows.sh`, `templates/README.txt`, `tests/test_package_windows.sh`

**Interfaces:**
- Consumes: `fetch.sh`, `trim-plugins.sh --mode category`, `lists/windows-*.txt`.
- Produces: `scripts/package-windows.sh <maven-version> <vlc-version> <out-dir>` → `<out-dir>/vlc-windows-x64-<maven-version>.zip` and `<out-dir>/vlc-windows-x64-<maven-version>.trim.txt` (trim report). Env `VLC_WIN_ZIP` = path to an already-downloaded zip skips `fetch.sh` (used by tests). Runs on Linux, macOS or Git Bash.

- [ ] **Step 1: Failing test** with a fixture zip `vlc-3.0.24/{libvlc.dll,libvlccore.dll,axvlc.dll,npvlc.dll,vlc.exe,COPYING.txt,AUTHORS.txt,plugins/plugins.dat,plugins/codec/x.dll,plugins/gui/y.dll}` and small fixture lists: output zip lists exactly `VLC/libvlc.dll VLC/libvlccore.dll VLC/COPYING.txt VLC/AUTHORS.txt VLC/README.txt VLC/plugins/codec/x.dll` (plus directory entries); `README.txt` contains `3.0.24` and the source URL; report contains `REMOVED gui`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement: unzip to temp, rename top folder to `VLC`, delete everything at top level except core DLLs and licence files, delete `plugins/plugins.dat`, trim, render README from template (`sed s/@VLC_VERSION@/…/`), `zip -r -X`. Lists path overridable with env `LISTS_DIR` for tests.
- [ ] **Step 4:** Run → pass. Then run for real: `scripts/package-windows.sh 3.0.24 3.0.24 build/out`; confirm zip size and that no `UNCLASSIFIED` appears.
- [ ] **Step 5:** Commit `Build the trimmed Windows VLC package`.

### Task 6: macOS package and binary checks

**Files:** Create `scripts/package-macos.sh`, `scripts/verify-macos.sh`, `tests/test_verify_macos.sh`, `tests/test_package_macos.sh`

**Interfaces:**
- Consumes: `fetch.sh`, `trim-plugins.sh --mode flat`, `lists/macos-*.txt`, `templates/README.txt`.
- Produces: `scripts/verify-macos.sh <MacOS-dir>` → for every Mach-O under `lib/` and `plugins/`: fails if `lipo -archs` lacks `arm64` or `x86_64`; rewrites any dependency on `libvlc*.dylib`/`libvlccore*.dylib` that is not `@rpath/` or `@loader_path/` to `@rpath/<unversioned-name>` with `install_name_tool`, then re-signs that file with `codesign --force -s -`; prints `FIXED <file> <old> -> <new>` per change; exit 0 when all files pass.
- Produces: `scripts/package-macos.sh <maven-version> <vlc-version> <out-dir>` → `<out-dir>/vlc-macos-<maven-version>.zip` and `.trim.txt`. Env `VLC_MAC_APP` = path to an existing `VLC.app` skips download/mount (tests). macOS only.

- [ ] **Step 1: Failing tests** (skip with a PASS-and-note when `uname` ≠ Darwin):
  - `test_verify_macos.sh`: build tiny dylibs with `clang -dynamiclib -arch arm64 -arch x86_64`: universal `libvlccore.dylib`; a plug-in linked to it by absolute path → after verify, `otool -L` shows `@rpath/libvlccore.dylib`, `codesign -v` passes, output has `FIXED`; an arm64-only plug-in → verify fails.
  - `test_package_macos.sh`: fixture `VLC.app/Contents/MacOS/lib/` with `libvlc.5.dylib` + symlink `libvlc.dylib`, `libvlccore.9.dylib` + symlink `libvlccore.dylib`, plus `plugins/` with a universal kept plug-in, a universal removed plug-in and an x86_64-only plug-in; output zip has `lib/libvlc.dylib` and `lib/libvlccore.dylib` as regular files (`zipinfo` mode not `l`), no versioned names, no `__MACOSX`, no `._` entries; removed and x86_64-only plug-ins absent; report contains `REMOVED` for both (`REMOVED <name> (not universal)` for the latter).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `verify-macos.sh`.
- [ ] **Step 4:** Implement `package-macos.sh`: fetch DMG, `hdiutil attach -nobrowse -readonly -mountpoint <tmp>` with a `trap` that detaches; copy `lib/libvlc.dylib` and `lib/libvlccore.dylib` with `cp -L`, copy `plugins/*.dylib`; remove non-universal plug-ins; trim; verify; licence files + README; `ditto -c -k --norsrc --noextattr --keepParent VLC.app` or `zip -r -X -y` from the staging dir.
- [ ] **Step 5:** Run tests → pass. Run for real: `scripts/package-macos.sh 3.0.24 3.0.24 build/out`; confirm the six `mmx`/`sse2` plug-ins are reported removed, zero `UNCLASSIFIED`.
- [ ] **Step 6:** Commit `Build the trimmed universal macOS VLC package`.

**Phase 1 checkpoint:** update issue #1 with a summary; pause for review.

---

## Phase 2 — Smoke test and CI

### Task 7: vlcj smoke test

**Files:** Create `smoke/pom.xml`, `smoke/src/main/java/ca/phon/vlcsmoke/SmokeTest.java`, `smoke/allowed-errors.txt`, `smoke/make-clips.sh`, `smoke/clips/{video.mp4,video.mov,audio.wav,audio.mp3,audio.m4a}`

**Interfaces:**
- Produces: `mvn -q -f smoke/pom.xml -Dvlcj.version=<v> package` → `smoke/target/vlc-smoke.jar` (shaded, main class `ca.phon.vlcsmoke.SmokeTest`).
- Produces: `java -jar smoke/target/vlc-smoke.jar <vlc-lib-dir> <clips-dir>` with env `VLC_PLUGIN_PATH=<plugins-dir>` → prints one line per clip `PASS <clip>` or `FAIL <clip>: <reason>`, exits 0 only if all pass. Prints vlcj and libvlc versions first.

Checks per clip (timeout = clip duration + 20 s):
- `NativeLibrary.addSearchPath(RuntimeUtil.getLibVlcLibraryName(), libDir)`; `new MediaPlayerFactory("--no-metadata-network-access", "--no-plugins-cache", "--aout=adummy")`.
- Video clips: callback video surface (`BufferFormatCallback` + `RenderCallback`, as in Phon's `PhonMediaPlayer`) receives ≥ 1 frame; `snapshots().save(file)` returns true and file size > 0.
- All clips: `finished()` event fires.
- Native log (`factory.application().newLog()`, level `ERROR`): any message not matching a regex in `allowed-errors.txt` fails the clip.

- [ ] **Step 1:** Write `make-clips.sh` (ffmpeg `testsrc`/`sine`, 3 s, 320×240): MP4 and MOV (H.264 + AAC), WAV (PCM s16le), MP3, M4A (AAC). Run it; commit clips (each < 200 KB).
- [ ] **Step 2:** Write `SmokeTest.java` and `pom.xml` (Java 21, vlcj version property default `4.12.1`, maven-shade-plugin).
- [ ] **Step 3: Negative check:** run against the Task 6 package with `libavcodec_plugin.dylib` deleted from a copy → `FAIL` for every clip, exit ≠ 0.
- [ ] **Step 4:** Run against the intact Task 6 package with `-Dvlcj.version=4.12.1` and `4.11.0` → all `PASS`, exit 0. Add any benign ERROR lines seen to `allowed-errors.txt` with a comment explaining each.
- [ ] **Step 5:** Commit `Add vlcj smoke test for VLC packages`.

### Task 8: GitHub Actions workflow and publish script

**Files:** Create `.github/workflows/build.yml`, `scripts/publish.sh`; update `README.md` (bump + release instructions, the one-time package access grant)

**Interfaces:**
- Consumes: every script above, `smoke/`.
- Produces: `scripts/publish.sh <artifact-id> <version> <zip>` → if `https://maven.pkg.github.com/speechmetrics/package-vlc-phon/org/videolan/<artifact-id>/<version>/<artifact-id>-<version>.pom` returns 200 (authenticated with `GITHUB_TOKEN`), prints `SKIP <artifact-id> <version> already published` and exits 0; else `mvn deploy:deploy-file -DgroupId=org.videolan -DartifactId=<id> -Dversion=<v> -Dpackaging=zip -Dfile=<zip> -DrepositoryId=github -Durl=<repo-url>` with a generated `settings.xml` using `GITHUB_ACTOR`/`GITHUB_TOKEN`.

Workflow `build.yml`:
- Triggers: `push` tags `v*`, `pull_request`, `workflow_dispatch`.
- `version` job (ubuntu): `tests/run.sh`; `resolve-version.sh "$GITHUB_REF_NAME"` (tag only; else no arg) → outputs.
- `package-macos` (`macos-15`) and `package-windows` (`ubuntu-latest`): run package script; upload zip + `.trim.txt` as artifacts.
- `smoke` matrix: `{runner: macos-15, pkg: macos}`, `{runner: macos-15-intel, pkg: macos}`, `{runner: windows-latest, pkg: windows}` × `vlcj: [4.11.0, 4.12.1]`; `actions/setup-java` temurin 21; unzip artifact; set `VLC_PLUGIN_PATH`; build and run smoke jar.
- `publish` (tag only, `needs: smoke`, `permissions: {contents: write, packages: write}`): `publish.sh` for both artifacts; `gh release create <tag>` with both zips, a `SHA256SUMS` file, and notes built from the two `.trim.txt` reports (removed list + any `UNCLASSIFIED`).

- [ ] **Step 1:** Write `publish.sh` and the workflow.
- [ ] **Step 2:** Push the branch and open the PR; confirm every job except `publish` passes and `publish` is skipped. Read the smoke logs for all six combinations.
- [ ] **Step 3:** Test `publish.sh` skip path locally: point it at the existing `org.videolan:vlc-macos:3.0.17` with a token holding `read:packages` → prints `SKIP`.
- [ ] **Step 4:** Commit `Build, test and publish VLC packages in CI`.

**Phase 2 checkpoint:** update issue #1; pause for review; merge PR into `main`.

---

## Phase 3 — Release and adoption

### Task 9: First release

- [ ] **Step 1:** Owner grants `speechmetrics/package-vlc-phon` write access to packages `org.videolan.vlc-macos` and `org.videolan.vlc-windows-x64` (package settings → Manage Actions access). Wait for confirmation.
- [ ] **Step 2:** Tag `v3.0.24` on `main` and push.
- [ ] **Step 3:** Confirm the workflow publishes both versions and the GitHub Release lists the zips, `SHA256SUMS` and removed plug-ins.
- [ ] **Step 4:** Update issue #1.

### Task 10: Adopt in Phon

- [ ] **Step 1 (phon-4.x):** branch from `dev`; set `vlcj = "4.12.1"` in `gradle/libs.versions.toml`; `./gradlew :media:build`; PR into `dev`.
- [ ] **Step 2 (phon-package):** set `org.videolan.vlc-macos.version` and `org.videolan.vlc-windows.version` to `3.0.24` in `pom.xml`; run `mvn validate` and confirm `target/external-resources/vlc/macos-universal/VLC.app/Contents/MacOS/{lib,plugins}` and `.../win-x64/VLC/` unpack. Leave the change uncommitted (phon-package is not committed by Claude).
- [ ] **Step 3:** Owner builds a beta installer; confirm on Apple silicon that media plays and the "Support Ending for Intel-based Apps" warning no longer appears, and that the bundle has no non-universal Mach-O files:
  `find <app> -type f -exec sh -c 'a=$(lipo -archs "$1" 2>/dev/null) && case "$a" in *arm64*) ;; *) echo "$a $1";; esac' _ {} \;` → only the arch-specific chatter/flatlaf siblings.
- [ ] **Step 4:** Update and close issue #1.
