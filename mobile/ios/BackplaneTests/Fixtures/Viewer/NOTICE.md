# The board viewer's sample

The captures here (`board.capture`, `schematic.capture`, `3d.capture`) are
what a hub sent a phone watching the layout, the root schematic sheet and the
3D model of the **RoyalBlue54L Feather**, and the viewer snapshots in
`BackplaneTests/__Snapshots__/SnapshotTests/viewer*.png` are drawn from them.

- Design: RoyalBlue54L Feather by Lord's Boards
  (https://www.crowdsupply.com/lords-boards/royalblue54l-feather), as shipped
  in KiCad's source at `demos/royalblue54L_feather`, commit
  `7f2d789cd59318048e3419f0628777197a287464`
  (https://gitlab.com/kicad/code/kicad).
- Licence: CERN Open Hardware Licence Version 2 – Permissive (CERN-OHL-P v2),
  in `LICENSE-CERN-OHL-P.txt`. These files are derived from that design and
  are under that licence, not the rest of this repository's MIT licence.
- Modified: the copy captured names its parts' STEP models where the design
  names VRML (`.wrl` to `.step` in its model paths), since the 3D model is
  made from KiCad's STEP library. Nothing else was changed.

`scripts/apple-viewer-fixtures.sh` fetches the design at that commit and
captures these again.
