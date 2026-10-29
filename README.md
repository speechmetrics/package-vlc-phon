# package-vlc-phon

Builds the trimmed VLC runtime packages that the Phon installers bundle:

- `ca.phon.vlc:vlc-macos` — universal `VLC.app/Contents/MacOS/{lib,plugins}`
- `ca.phon.vlc:vlc-windows-x64` — `VLC/{libvlc.dll,libvlccore.dll,plugins}`

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
2. Regenerate the lists and licence files on a Mac:
   `scripts/seed-lists.sh <version> build/seed`. If it reports unmatched Mac
   plug-ins, add them to `lists/macos-only.tsv` and re-run. Review the
   differences with `lists/`, then copy
   `build/seed/{windows,macos}-{keep,remove}.txt` into `lists/`.
3. Open a pull request and check the build and smoke tests pass.
4. After merging, tag `main` with `v<version>` and push the tag.
5. In `phon-package/pom.xml`, set both VLC versions to the new version.

To republish the same VLC with changed lists, tag `v<version>-<n>`
(for example `v3.0.24-2`). Published versions cannot be overwritten.

## Package names and access

The packages are `ca.phon.vlc:vlc-macos` and `ca.phon.vlc:vlc-windows-x64`,
published from this repository with the workflow's own token. A Maven package
on GitHub takes its access from the repository it is linked to, so no extra
grant or secret is needed. The hand-built `org.videolan` packages (VLC 3.0.17
and 3.0.12) stay linked to `phon-package` for older builds; this repository
cannot publish to them.

## Licence

The scripts in this repository are provided for building Phon. The packages
they produce contain VLC, which is free software released under the GNU GPL
and GNU LGPL by VideoLAN; see `licenses/`.
