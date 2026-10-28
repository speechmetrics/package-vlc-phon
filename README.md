# package-vlc-phon

Builds the trimmed VLC runtime packages that the Phon installers bundle:

- `org.videolan:vlc-macos` — universal `VLC.app/Contents/MacOS/{lib,plugins}`
- `org.videolan:vlc-windows-x64` — `VLC/{libvlc.dll,libvlccore.dll,plugins}`

See `docs/superpowers/specs/2026-10-28-vlc-packaging-design.md` for the design.

## Tests

```bash
tests/run.sh
```
