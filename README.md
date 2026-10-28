# package-vlc-phon

Builds the trimmed VLC runtime packages that the Phon installers bundle:

- `org.videolan:vlc-macos` — universal `VLC.app/Contents/MacOS/{lib,plugins}`
- `org.videolan:vlc-windows-x64` — `VLC/{libvlc.dll,libvlccore.dll,plugins}`

See `docs/superpowers/specs/2026-10-28-vlc-packaging-design.md` for the design.

## Tests

```bash
tests/run.sh
```

## How it works

On every pull request, manual run and `v*` tag, `.github/workflows/build.yml`:

1. runs `tests/run.sh` and resolves the version (`scripts/resolve-version.sh`);
2. builds both packages from VideoLAN's official downloads, verified against
   their SHA-256 checksums (`scripts/package-macos.sh`, `scripts/package-windows.sh`);
3. plays the clips in `smoke/clips` through each package with vlcj 4.11.0 and
   4.12.1 on Apple silicon macOS, Intel macOS and Windows (`smoke/`);
4. on a tag only, publishes both zips to GitHub Packages and creates a GitHub
   Release listing the removed plug-ins (`scripts/publish.sh`).

Plug-ins are trimmed with the lists in `lists/`. A plug-in on neither the keep
nor the remove list is kept and shown as `UNCLASSIFIED` in the build log and
the Release notes; add it to one of the lists.

## Updating VLC

1. Put the new version in `VLC_VERSION`.
2. Re-seed the lists and licence files on a Mac:
   `scripts/seed-lists.sh <version> build/seed`. Compare `build/seed/*` with
   `lists/` and place anything in `build/seed/macos-unmatched.txt` by hand.
3. Open a pull request and check the build and smoke tests pass.
4. After merging, tag `main` with `v<version>` and push the tag.
5. In `phon-package/pom.xml`, set `org.videolan.vlc-macos.version` and
   `org.videolan.vlc-windows.version` to the new version.

To republish the same VLC with changed lists, tag `v<version>-<n>`
(for example `v3.0.24-2`). Published versions cannot be overwritten.

## One-time setup

GitHub Packages links each package to the repository that first published it.
Before the first release, open each of `org.videolan.vlc-macos` and
`org.videolan.vlc-windows-x64` in the speechmetrics organisation's packages,
and under **Manage Actions access** give this repository the **Write** role.

## Licence

The scripts in this repository are provided for building Phon. The packages
they produce contain VLC, which is free software released under the GNU GPL
and GNU LGPL by VideoLAN; see `licenses/`.
