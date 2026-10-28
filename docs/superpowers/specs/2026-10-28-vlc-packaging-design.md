# VLC packages for Phon: design

Date: 2026-10-28

## Intent

Phon plays media through vlcj, which needs a VLC runtime shipped inside the
Phon installers. Today that runtime comes from two zips in speechmetrics
GitHub Packages (`org.videolan:vlc-macos:3.0.17`,
`org.videolan:vlc-windows-x64:3.0.12`). They were assembled by hand more than a
year ago: download VLC, copy out the core libraries and plug-ins, fix library
load paths, zip, upload. Nobody remembers the exact steps, so the runtime has
not been updated since.

That stale runtime now causes a user-facing problem. macOS shows "Support
Ending for Intel-based Apps … includes a component that will not work with a
future release of macOS" for Phon. The cause is six Intel-only plug-ins in the
Mac package (`libi420_rgb_mmx`, `libi420_rgb_sse2`, `libi420_yuy2_mmx`,
`libi420_yuy2_sse2`, `libi422_yuy2_mmx`, `libi422_yuy2_sse2`). Phon starts VLC
with `--no-plugins-cache`, so VLC loads every plug-in at each start, including
these.

This repository, `speechmetrics/package-vlc-phon`, replaces the manual process
with a scripted, repeatable build that runs on GitHub Actions and publishes
when a tag is pushed.

## Goals

- Build the macOS and Windows VLC packages from official VideoLAN releases with
  no manual steps.
- Remove every Mac binary that lacks an Apple silicon build, which ends the
  macOS warning.
- Remove plug-ins Phon cannot use.
- Prove each package works with Phon's vlcj before publishing it.
- Publish under the same Maven coordinates and zip layout as today, so
  `phon-package` only changes version numbers.
- Make a VLC update a one-line change plus a tag.

## Non-goals

- Linux packages. Phon does not bundle VLC on Linux.
- Separate Intel and Apple silicon Mac packages. The Mac package stays
  universal because the Phon installer is universal.
- Code signing and notarization. install4j signs and notarizes every binary in
  the installer, as it does today.
- VLC 4 or vlcj 5. vlcj 5 is still at milestone releases (5.0.0-M6) and needs
  VLC 4, which is unreleased.
- Building VLC from source.

## Anti-goals

- A package that builds and publishes but fails to play media in Phon. The
  smoke test exists to prevent this; a smoke test failure blocks publishing.
- Silent changes. Every plug-in removed, and every plug-in kept that the lists
  do not mention, appears in the build log.
- Overwriting a published version. Each build gets a new version number.

## Constraints

- **Versions.** vlcj 4.12.1 is the newest stable vlcj and supports VLC 3.0.x.
  VLC 3.0.24 is the newest VLC 3 release. The first build targets VLC 3.0.24.
  Phon moves from vlcj 4.11.0 to 4.12.1 in a separate change in `phon-4.x`.
- **Sources.** VideoLAN publishes, under `https://get.videolan.org/vlc/3.0.24/`:
  - `macosx/vlc-3.0.24-universal.dmg` (+ `.sha256`)
  - `win64/vlc-3.0.24-win64.zip` (+ `.sha256`)
  The build verifies each checksum before using the download.
- **Package layout must not change.** install4j copies
  `target/external-resources/vlc/macos-universal/VLC.app` and
  `target/external-resources/vlc/win-x64/VLC`, and Phon is launched with
  `-Dca.phon.media.VLCHelper.vlcLocation=bin/VLC.app/Contents/MacOS/lib` /
  `bin\VLC` and `…vlcPluginPath=…/plugins`. Therefore:
  - Mac zip root: `VLC.app/Contents/MacOS/lib/{libvlc.dylib,libvlccore.dylib}`
    and `VLC.app/Contents/MacOS/plugins/*.dylib` (flat folder).
  - Windows zip root: `VLC/{libvlc.dll,libvlccore.dll}` and
    `VLC/plugins/<category>/*.dll`.
  - No `__MACOSX/` or `._*` entries in the Mac zip (the 3.0.17 zip had them).
- **Load paths.** Mac libraries and plug-ins must reference each other through
  `@rpath` or `@loader_path` only, never an absolute path. The current
  3.0.17 package does this; the build must check it and fix any that differ
  with `install_name_tool`.
- **Plug-in cache.** Phon uses `--no-plugins-cache`, so no `plugins.dat` is
  shipped; a stale one after trimming would be wrong anyway.
- **Licence.** VLC is LGPL/GPL. Each zip includes VLC's `COPYING` and
  `AUTHORS` files and a short `README` naming the VLC version and linking to
  `https://code.videolan.org/videolan/vlc/-/tree/3.0.24` (version substituted).
- **Repository is public**, so Actions minutes are free and the packages are
  public.

## How Phon uses VLC

Recorded here because it decides what can be trimmed
(`phon-4.x/media/src/main/java/ca/phon/media/player/PhonMediaPlayer.java`):

- Local files only. `--no-metadata-network-access`.
- Video is drawn through vlcj's callback surface
  (`newVideoSurface(BufferFormatCallback, RenderCallback, true)`), which uses
  VLC's `vmem` video output.
- Audio uses VLC's default audio output.
- Snapshots are taken with `mediaPlayer.snapshots()`.
- No VLC interface, no streaming, no recording or transcoding.

## Trimming policy

**Keep** the core libraries and these plug-in categories: `access`, `demux`,
`codec`, `packetizer`, `audio_output`, `audio_filter`, `audio_mixer`,
`video_output`, `video_chroma`, `video_filter`, `stream_filter`, `misc`,
`text_renderer`, `spu`, `meta_engine`, `logger`, plus `d3d9` and `d3d11` on
Windows.

**Remove**:

- `gui` (Qt, skins2, the macOS player window), `control` (hotkeys, HTTP/telnet
  remote control, etc.), `lua`, `services_discovery`, `stream_out`,
  `access_output`, `mux`, `visualization`, `keystore`, `video_splitter`,
  `stream_extractor`.
- Windows browser plug-ins `axvlc.dll` and `npvlc.dll`, and everything at the
  top of the VLC folder other than the two core DLLs and the licence files.
- On Mac, every plug-in that is not universal (has no `arm64` slice or no
  `x86_64` slice). Intel Macs lose only the MMX/SSE2 colour converters and
  fall back to VLC's generic converters.

**How the lists are expressed** (builder's call, recorded): four plain text
files in the repo, a keep list and a remove list per platform, one entry per
line with comments, so they are easy to edit:

- Windows plug-ins are already in category folders, so the Windows lists are
  category folder names (`windows-keep.txt`, `windows-remove.txt`).
- Mac plug-ins sit in one flat folder, so the Mac lists are plug-in file names
  (`macos-keep.txt`, `macos-remove.txt`). Generate them once from VLC 3.0.24:
  sort each Mac plug-in into the category its Windows counterpart sits in, and
  place Mac-only plug-ins by hand (`libmacosx_plugin` → remove;
  `libauhal_plugin`, `libvideotoolbox_plugin`, `libcaopengllayer_plugin` →
  keep). Commit the result.
- A plug-in or Windows category on neither list is **unclassified**: it is
  kept and reported in the build log and the Release notes, so a VLC update
  never removes something by accident and new arrivals are visible.
- An entry on a list that no longer exists in the download is reported as a
  warning, so the lists don't drift.

## The build

Pushing a tag `v<vlc-version>` (for example `v3.0.24`) or
`v<vlc-version>-<n>` for a rebuild of the same VLC with different trimming
(for example `v3.0.24-2`) runs one workflow. The Maven version is the tag
without the `v`. The VLC version to download is the part before any `-<n>`.
The workflow also runs on pull requests and manual dispatch, doing everything
except publishing.

1. **macOS package job** (macOS runner):
   1. Download the universal DMG and its `.sha256`; verify.
   2. Mount the DMG; copy `VLC.app/Contents/MacOS/lib/libvlc.dylib`,
      `libvlccore.dylib` and `VLC.app/Contents/MacOS/plugins/` into a staging
      `VLC.app/Contents/MacOS/`; unmount.
   3. Apply the Mac removal list; remove non-universal plug-ins.
   4. Check every remaining Mach-O file is universal (`arm64` and `x86_64`).
   5. Check load paths (see Constraints); fix with `install_name_tool` if
      needed. If a path is changed, the existing VideoLAN signature breaks;
      re-sign that file ad hoc (`codesign -s -`) so it stays loadable until
      install4j signs it.
   6. Add licence files; zip as `vlc-macos-<version>.zip` without
      `__MACOSX` entries.
2. **Windows package job** (any runner):
   1. Download `win64.zip` and its `.sha256`; verify.
   2. Keep the core DLLs, `plugins/` and licence files; rename the top folder
      to `VLC`.
   3. Apply the Windows removal list; delete `plugins/plugins.dat`.
   4. Zip as `vlc-windows-x64-<version>.zip`.
3. **Smoke test jobs**, one per platform below, each using the package built
   in step 1 or 2. A small Java program built with vlcj 4.12.1 points vlcj at
   the unzipped package the same way Phon does (`NativeLibrary.addSearchPath`
   on the `lib` folder, `VLC_PLUGIN_PATH` on `plugins`) and creates its
   `MediaPlayerFactory` with Phon's options (`--no-metadata-network-access`,
   `--no-plugins-cache`). For each test clip it checks:
   - video frames arrive through a callback video surface (video clips);
   - the clip plays to its end (position reaches the end);
   - a snapshot can be saved (video clips);
   - VLC's log contains no error about a missing module or decoder
     (vlcj log listener).
   Platforms: macOS Apple silicon, macOS Intel, Windows x64.
   vlcj versions (builder's call, recorded): both 4.11.0 (what Phon ships
   today) and 4.12.1 (the planned bump), so the package is safe whichever
   follow-up change lands first.
   Test clips: a few seconds each, generated by a script in the repo with
   ffmpeg and committed (small files): MP4 (H.264 + AAC), MOV (H.264 +
   AAC), WAV (PCM), MP3, M4A (AAC). These are the formats Phon users load most.
4. **Publish job** (tags only, after all smoke tests pass):
   - Publish to the `speechmetrics` namespace
     (`https://maven.pkg.github.com/speechmetrics/package-vlc-phon`) with the
     workflow's built-in `GITHUB_TOKEN` (`packages: write`). The packages
     already exist there under another repo; the owner grants this repo
     write access in each package's settings before the first tag.
   - Deploy both zips to GitHub Packages as `org.videolan:vlc-macos:<version>`
     and `org.videolan:vlc-windows-x64:<version>`, packaging `zip`, with a
     minimal POM like the existing one.
   - Create a GitHub Release for the tag with both zips and their SHA-256
     sums, listing the removed plug-ins and any unclassified ones.

## Follow-up changes in other repos (not part of this repo)

- `phon-4.x`: bump vlcj 4.11.0 → 4.12.1 (`gradle/libs.versions.toml`).
- `phon-package`: bump `org.videolan.vlc-macos.version` and
  `org.videolan.vlc-windows.version` in `pom.xml` to the new version; build a
  beta installer and confirm the macOS warning is gone and media plays.

## Left to the builder

- Script language for packaging (shell is expected; anything available on the
  runners is fine) and how the workflow is split into files.
- How the smoke-test program is built and run (Maven, Gradle or plain
  `javac` with downloaded jars) and which JDK (21 or later).
- Exact runner labels, as long as they cover Apple silicon Mac, Intel Mac and
  Windows x64.
- Exact wording of the README and Release notes.
- How the smoke test handles runners without an audio device (for example
  VLC's `--aout=dummy` for the test only), provided decoding is still
  exercised.
