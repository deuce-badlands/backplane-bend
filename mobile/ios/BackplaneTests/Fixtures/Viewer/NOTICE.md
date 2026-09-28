# The board viewer's sample

The captures here (`board.capture`, `schematic.capture`, `3d.capture`) are
what a hub sent a phone watching the layout, the root schematic sheet and the
3D model of the **RoyalBlue54L Feather**, and the viewer snapshots
(`BackplaneTests/__Snapshots__/SnapshotTests/viewer*.png`, recorded locally,
not checked in) are drawn from them.

- Design: RoyalBlue54L Feather by Lord's Boards
  (https://www.crowdsupply.com/lords-boards/royalblue54l-feather), as shipped
  in KiCad's source at `demos/royalblue54L_feather`, commit
  `7f2d789cd59318048e3419f0628777197a287464`
  (https://gitlab.com/kicad/code/kicad). The KiCad project modified it before
  shipping it (its README: "Modified by KiCad Project Feb 17, 2025").
- Licence: the design's folder releases its hardware files under the CERN
  Open Hardware Licence Version 2 – Permissive (CERN-OHL-P v2), included here
  as `LICENSE-CERN-OHL-P.txt` (identical to that folder's `LICENSE`). KiCad's
  `LICENSE.README` also lists every file under `demos/` as CC BY-SA 4.0
  (https://creativecommons.org/licenses/by-sa/4.0/). These captures are
  derived from the design under those terms, not under the rest of this
  repository's MIT licence.
- 3D models: `3d.capture` carries the parts' geometry as meshed from KiCad's
  3D model library, which is CC BY-SA 4.0 with an exception waiving article 3
  for designs and generated files that use it
  (https://www.kicad.org/libraries/license/).
- Modified by the Backplane project, 2026-09-27: the copy captured names its
  parts' STEP models where the design names VRML (`.wrl` to `.step` in its
  model paths), since the 3D model is made from KiCad's STEP library. Nothing
  else in the design was changed; the captures are the hub's rendering of it.

`scripts/apple-viewer-fixtures.sh` fetches the design at that commit and
captures these again.
