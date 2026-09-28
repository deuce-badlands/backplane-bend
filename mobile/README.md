# Phone apps

Native iOS (SwiftUI) and Android (Jetpack Compose) clients for a Backplane
hub. The client logic is the same Bend the web page runs: `src/mobile/`
turns `core/client.bend`'s `Ui` into a screen model (JSON), and
`bridge.js` carries strings between it and the app. The apps own the socket
and draw the screen with native lists, toolbars and text fields; they make
no product decisions. iOS runs the bridge in JavaScriptCore, Android in
QuickJS.

```sh
scripts/build-mobile.sh           # bridge.js + dist/backplane-android.apk
scripts/build-ios.sh sim          # build on the Mac, run in the Simulator
scripts/build-ios.sh archive      # sign and upload to TestFlight
```

`build-ios.sh` bundles bridge.js here (bend), rsyncs `mobile/ios` to
`~/backplane-ios` on the Mac (`BACKPLANE_MAC`, default `hs-mac-mini`) and
runs xcodebuild there. Debug builds read `BACKPLANE_LINK` and
`BACKPLANE_SELECT` from the environment (`SIMCTL_CHILD_…`) to pair and open
a thread without taps.

Pairing: paste the hub's tailnet link (`http://host:3787/#token=…`), or open
`backplane://pair?url=<that link, URL-encoded>`.

Kept state: each app writes the Bend client's whole state down (a file
named `state-<key>.json`) and loads it at launch, then asks each hub only
for what came since. The key is a hash of the Bend type definitions
(`scripts/state-key.py`, stamped at the end of bridge.js by
`build-mobile.sh`), so a new build keeps the state unless a type changed.

Several hubs: the phone stays connected to every hub it pairs with, one
socket and one Bend client each (`src/mobile/hubs.bend`, keyed by
host:port). The screen is all of them in one: each hub's projects, named
by machine when there are several; alerts and the island from all; the
thread of the hub in focus (the one whose thread was opened last). Ids on
the screen carry their hub (`host:port|id`), and Bend routes each action
by that prefix (laws `hubs_*`, test `test/hubs_test.bend`). The link
button lists the paired hubs (unpair there), the owner's other machines
they know of (one tap pairs), and takes a new link. Only the hub in focus
draws plots. Debug builds take several links in `BACKPLANE_LINK`,
separated by spaces.

## A thread on the phone

The screen carries what the web client's thread view has, decided in
`src/mobile/screen.bend`: asks (approve, answer, implement a plan), runs
of tool calls folded (`fold`), subagents and links between threads,
attachments (the app reads a photo or file and sends it through `attach`
in the pieces the screen names), the images a reply names (served by the
hub at `/img` with the pairing token; only the newest 40 entries look,
since finding them walks the text), `$skill` completion, the diff and git
actions, the terminal (the hub's VT emulator, keys through `term-key` and
`term-paste`), search and the file picker (`find-open`), settings, and
the archived shelf. Debug builds read `BACKPLANE_ACTS`
(`action=value;;…`, two seconds apart once the thread is open;
`@attach` uploads a test image) to drive these without hands.

## Board viewer

A thread's toolbar opens its project's board, schematic or 3D model (the
chip icon). The hub sends a plot (`src/core/plot.bend`) as CBOR written
straight by Bend: chunks of geometry in paint order, then, on each save,
only the chunks that changed (laws `plot_delta_exact`,
`plot_unchanged_sends_nothing`). Plot frames go straight from the socket
to the renderer, never through bridge.js.

The phone uploads a plot to the GPU once; pan, pinch, double-tap and (in
3D) orbit only move a transform, so every frame costs the same whatever
the board. Each layer is drawn as coverage (tracks, arcs and dots as
instanced capsules with an analytic edge, fills by stencil) and laid over
the frame in its colour and opacity. Frames are drawn only while a finger
moves, a fling coasts or new chunks fade in. iOS: Metal (shaders compiled
on the device, so the build needs no Metal toolchain), up to 120 Hz.
Android: OpenGL ES 3.

A tap is inspected on the phone: it hit-tests its own geometry, Bend picks
the smallest piece under the finger (laws `pick_*`), and the hub answers
with that piece's info from the chunks this phone holds; the card offers
"Mention in chat". 3D draws the board's body and parts (kicad-cli, exported
by the hub in a child process) with the plot's layers laid sharp on its
faces; before the model arrives, a slab of the board's thickness.

3D moves like SolidWorks: the camera turns freely (no up axis, no limit)
about the centre of the board's rectangle (the plot's `edge`, its
Edge.Cuts box) halfway through its thickness, which keeps its place on
screen after a pan. One
finger turns the model under it (about the screen's axes), two fingers
drag it, pinch zooms toward the fingers, twisting two fingers rolls it
about the view axis, and a double tap fits it again. The model is drawn 4x
multisampled; the layers on its faces keep their analytic edge.

Debug builds also read `BACKPLANE_VIEW` (board, schematic, 3d) and
`BACKPLANE_TAP` (x,y in points) to open the viewer and tap without hands.

## On a Mac

The same app builds natively for macOS 14+ on Apple silicon (not Mac
Catalyst): one target, destinations iPhone, iPad and Mac.
`scripts/build-ios.sh mac` builds it here (not over SSH), checks it is
sandboxed and opens it. `BACKPLANE_TEAM=<team id>` signs it with that team;
without one it is signed to run locally.

- Pair it with a hub on the same Mac as `127.0.0.1:3787`: loopback is
  trusted, so no token. A hub elsewhere pairs as on a phone.
- Projects, threads and bots sit in a sidebar; the selected one fills the
  rest of the window. The board viewer opens as a pane beside the thread,
  resizable by its divider, with its own light or dark ground. The same
  layout serves an iPad whenever its width is regular (a narrow iPad, as in
  Slide Over, and every iPhone keep the pushed list and full-screen
  viewer); under 900 pt wide the board stacks above the thread instead of
  beside it. On the Mac the viewer reads
  the mouse, trackpad and keys the way the desktop viewer does: a drag turns
  the 3D model (ctrl pans, shift zooms, alt rolls; right drag pans) or moves
  the board; a mouse wheel zooms at the pointer, forward out; two fingers
  on a trackpad move the board (or turn the model), pinch zooms, twist
  rolls; a click inspects, a double click fits or zooms; 1-7 are the
  standard views, arrows turn 15 degrees (90 with shift), z / shift+z zoom,
  f fits.
- cmd+return sends, opt+cmd+return sends with the other follow-up mode;
  swipe actions are also on the right-click menu; the terminal takes the
  keyboard directly.
- What differs lives in `mobile/ios/Backplane/Platform.swift`. The Dynamic
  Island (Live Activities) is iOS-only, so the Mac posts its own turn-end
  alerts while it runs behind other windows; hub push (APNs) is iOS-only
  for now.
- The Mac build is always sandboxed (`Backplane-macOS.entitlements`): the
  kept state lives in the app's container, never the shared
  `~/Library/Application Support`.

## Tests

The iPhone, iPad and Mac app has three layers of tests:

- **Bend** (`scripts/test.sh`, with the rest of the Bend tests):
  - `test/msettings_test.bend` checks what Settings shows against a mock hub: the sections, what each has set, what needs you, and every row's control and actions.
  - The mock hub (`test/mockhub.bend`) builds a hub's frames from the model's own changes and the hub's codec, so it cannot drift from what a hub sends.
- **Swift Testing** (`mobile/ios/BackplaneTests`, iOS and macOS, hosted in the app):
  - Each scene of the mock hub (`test/apple_fixtures.bend`, written to `BackplaneTests/Fixtures` by `scripts/apple-fixtures.sh`) is replayed through the real `bridge.js`.
  - Every answer must decode with a throwing decoder. A field renamed on either side fails with its path (`Out.decode` would drop the screen silently).
  - Also covered: what each scene shows, through `AppModel` itself; what the app asks the hub for; the question dock's answers; the Settings layout; pairing links; and the board viewer's decoding.
  - `scripts/test.sh` fails when a Bend change would alter the fixtures and they were not written again.
- **Snapshots** (swift-snapshot-testing, a test-only dependency): every scene on iPhone, iPad and Mac, in `BackplaneTests/__Snapshots__/SnapshotTests`. They double as pictures of the app on every device. The references are recorded locally and not checked in (`mobile/ios/.gitignore`), so CI runs every suite but this one (`BACKPLANE_TEST_SNAPSHOTS=0`).
- **The board viewer** is snapshotted on a sample board: KiCad's RoyalBlue54L Feather demo. Its captures are under the design's licences (CERN-OHL-P v2, and KiCad's CC BY-SA 4.0 for its demos and 3D library), not this repository's MIT; see `BackplaneTests/Fixtures/Viewer/NOTICE.md`.
  - The layout, schematic and 3D frames are captured from a real hub by `scripts/apple-viewer-fixtures.sh`. It fetches the demo at a pinned KiCad commit and runs a hub of its own (own port and home).
  - The tests feed the captures to the app as the socket would.
  - A Metal layer draws only on a screen, so under tests the canvas also shows its frame as a still image (`PlotRenderer.image(of:)`), which the snapshots take.

```sh
scripts/test-apple.sh                      # macOS, then the iOS 26.4 simulators (iPhone 17 Pro, iPad Pro 11-inch (M5)); all run, any failing fails
scripts/test-apple.sh mac                  # or one of them
SNAPSHOT_RECORD=all scripts/test-apple.sh  # record every snapshot again, then look at them
BACKPLANE_TEST_SNAPSHOTS=0 scripts/test-apple.sh mac   # all but the snapshots, as CI does
```

Or run the Backplane scheme's tests (⌘U) in Xcode.

How the snapshots are made:
- A missing snapshot is recorded and its test fails once, so a new image is looked at before it is kept.
- Record and compare on the same runtimes: the iOS 26.4 simulators, and macOS 26 with the Xcode 26.4 SDK. Other versions draw text a little differently.
- Each device is drawn by its own simulator, one after the other: the iPhone's images by an iPhone, the iPad's by an iPad (in an iPhone's window an iPad takes the iPhone's safe area). Animations are held still: layers at speed 0, and a cat at its first pose.
- The Mac tests run inside the sandboxed app, which cannot touch the source tree:
  - they read the reference images from the test bundle;
  - they compare them in the app's temporary directory;
  - the scheme's test post-action copies what they recorded back into `__Snapshots__`.
- An offscreen Mac view cannot draw a split view's Liquid Glass sidebar, so the Mac window images lay the sidebar and the detail side by side, as the split view does.

## TestFlight

`archive` needs `~/backplane-ios/signing.env` on the Mac (never committed):

```sh
TEAM_ID=XXXXXXXXXX                    # Apple Developer team
BUNDLE_ID=dev.backplane.mobile        # registered App ID; the app record uses it
ASC_KEY_ID=XXXXXXXXXX                 # App Store Connect API key (App Manager)
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH=/Users/h/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
```

## Notifications and the Dynamic Island

When a turn ends (Completed or Failed; a stop the user asked for is not
news), the phone alerts, and while turns run it shows a live status. What
counts is decided in `src/mobile/notify.bend` (laws `alert_*`).

- iOS in front: the app posts the alert itself and runs one Live Activity
  (lock screen + Dynamic Island) from the screen's `island`.
- iOS asleep: the hub pushes through APNs (`src/server/push.bend`): an
  alert, and Live Activity updates to the activity's push token. The app
  registers its tokens with the `device.register` rpc; tokens never leave
  the hub (laws `device_*`).
- Android: a foreground service keeps the socket open while turns run and
  shows an ongoing notification (promoted to a status-bar chip on Android
  16); alerts come from the same Bend `notify` commands.

APNs needs a key from developer.apple.com (Keys, with Apple Push
Notifications service enabled). Put the .p8 on the hub machine and set:

```
push.apns.key    /path/to/AuthKey_XXXXXXXXXX.p8
push.apns.keyid  XXXXXXXXXX
push.apns.team   <Team ID>
```

(settings via `setting.set`; only the path is stored, never the key).
Until all three are set (and the key file exists) the hub logs `backplane:
push: phones are registered but ...` at each turn end instead of pushing.
The key must belong to the team that owns the app's bundle id, or APNs
answers `TopicDisallowed`.
