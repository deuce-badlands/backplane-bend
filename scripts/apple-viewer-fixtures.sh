#!/bin/sh
# The Apple app's board viewer fixtures: what a hub sends a phone watching a
# sample board's layout, schematic and 3D model, captured from a real hub.
#
# The sample is KiCad's RoyalBlue54L Feather demo (demos/royalblue54L_feather
# in KiCad's source, CERN-OHL-P v2; see
# mobile/ios/BackplaneTests/Fixtures/Viewer/NOTICE.md), fetched at a pinned
# commit. A hub of its own (its own port and home, this checkout's
# dist/backplane) is asked to watch each view; every frame it sends until it
# goes quiet is kept, in order, as base64.
#   scripts/apple-viewer-fixtures.sh
# Needs dist/backplane built from this commit (scripts/build.sh), kicad-cli
# (the schematic, the 3D model) and backplane-step2glb (the 3D model). On a
# Mac the hub also needs GNU coreutils and findutils first on PATH.
set -eu
cd "$(dirname "$0")/.."
KICAD_COMMIT=7f2d789cd59318048e3419f0628777197a287464
DEMO=royalblue54L_feather
# where the sample sits while it is captured: the frames name this path, and
# test/apple_fixtures.bend's viewer project has the same root
ROOT=/tmp/backplane-sample/RoyalBlue54L-Feather
PORT=${BACKPLANE_CAPTURE_PORT:-3799}
out=mobile/ios/BackplaneTests/Fixtures/Viewer
[ -x dist/backplane ] || { echo "no dist/backplane: run scripts/build.sh"; exit 1; }
work=$(mktemp -d)
hub=""
cleanup() {
  [ -n "$hub" ] && kill "$hub" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# the demo, at the pinned commit, only its folder
git -c advice.detachedHead=false clone -q --filter=blob:none --no-checkout --sparse https://gitlab.com/kicad/code/kicad.git "$work/kicad"
git -C "$work/kicad" sparse-checkout set "demos/$DEMO"
git -C "$work/kicad" checkout -q "$KICAD_COMMIT"
rm -rf "$ROOT"
mkdir -p "$(dirname "$ROOT")"
cp -R "$work/kicad/demos/$DEMO" "$ROOT"
printf '{"pcb": "RoyalBlue54L-Feather.kicad_pcb", "schematic": "RoyalBlue54L-Feather.kicad_sch"}\n' > "$ROOT/.backplane.json"
# Most parts name KiCad's VRML models (.wrl). KiCad's 3D library ships STEP
# too (only STEP in the macOS app), and kicad-cli 10.0's `pcb export glb
# --subst-models` did not put the STEP in their place (44 of 71 parts came
# out without a model), so the copy captured names the STEP files.
perl -pi -e 's/(\(model "[^"]*)\.wrl"/$1.step"/g' "$ROOT/RoyalBlue54L-Feather.kicad_pcb"

# a hub of its own
mkdir -p "$work/home"
BACKPLANE_NO_UPDATE=1 dist/backplane --headless --foreground --no-tailscale --port "$PORT" --home "$work/home" > "$work/hub.log" 2>&1 &
hub=$!
i=0
until nc -z 127.0.0.1 "$PORT" 2>/dev/null; do
  i=$((i + 1))
  [ $i -lt 100 ] || { echo "the hub did not listen on $PORT"; cat "$work/hub.log"; exit 1; }
  sleep 0.2
done

mkdir -p "$out"
python3 - "$PORT" "$ROOT" "$out" <<'PY'
import base64, json, os, socket, struct, sys, time

port, root, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]

# CBOR, as much as a request needs: maps with text keys, text, ints
def cbor(v):
    def head(major, n):
        if n < 24: return bytes([major << 5 | n])
        if n < 256: return bytes([major << 5 | 24, n])
        if n < 65536: return bytes([major << 5 | 25]) + struct.pack(">H", n)
        return bytes([major << 5 | 26]) + struct.pack(">I", n)
    if isinstance(v, bool): return b"\xf5" if v else b"\xf4"
    if isinstance(v, int): return head(0, v)
    if isinstance(v, str):
        b = v.encode()
        return head(3, len(b)) + b
    if isinstance(v, dict):
        return head(5, len(v)) + b"".join(cbor(k) + cbor(x) for k, x in v.items())
    raise TypeError(v)

# a WebSocket client, as much as the hub needs: binary frames, masked out
s = socket.create_connection(("127.0.0.1", port))
key = base64.b64encode(os.urandom(16)).decode()
s.sendall((f"GET /ws?enc=cbor HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
           f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
buf = b""
while b"\r\n\r\n" not in buf:
    buf += s.recv(4096)
head, buf = buf.split(b"\r\n\r\n", 1)
if b" 101 " not in head.split(b"\r\n")[0]:
    sys.exit("the hub refused the socket: " + head.decode(errors="replace"))

def send(payload):
    mask = os.urandom(4)
    n = len(payload)
    h = bytes([0x82]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n) if n < 65536 else bytes([0x80 | 127]) + struct.pack(">Q", n))
    s.sendall(h + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

def take(n):
    global buf
    while len(buf) < n:
        chunk = s.recv(1 << 20)
        if not chunk: raise EOFError
        buf += chunk
    b, buf = buf[:n], buf[n:]
    return b

# the next whole message, or None after `wait` seconds of silence
def message(wait):
    s.settimeout(wait)
    try:
        data = b""
        while True:
            b0, b1 = take(2)
            n = b1 & 127
            if n == 126: n = struct.unpack(">H", take(2))[0]
            if n == 127: n = struct.unpack(">Q", take(8))[0]
            payload = take(n)
            op = b0 & 15
            if op == 9:
                continue
            data += payload
            if b0 & 0x80:
                return data
    except socket.timeout:
        return None
    finally:
        s.settimeout(None)

# a plot frame: a map whose first key is 1 ("t") and value "plot"
def is_plot(d):
    return len(d) > 7 and 0xA0 <= d[0] <= 0xB7 and d[1] == 1 and d[2:7] == b"dplot"

# what the hub sends on connect (its log) is not a viewer's
while message(2) is not None:
    pass

rid = 1
def watch(kind, quiet, limit):
    global rid
    rid += 1
    send(cbor({"id": rid, "m": "kicad.watch", "p": {"kind": kind, "root": root, "path": ""}}))
    frames, plots, start, last = [], 0, time.time(), time.time()
    while time.time() - start < limit:
        m = message(quiet if plots else limit)
        if m is None:
            break
        frames.append(m)
        plots += is_plot(m)
        last = time.time()
    if not plots:
        sys.exit(f"{kind}: no plot within {limit} s")
    return frames

for kind, quiet, limit in [("board", 3, 120), ("schematic", 3, 120), ("3d", 10, 600)]:
    frames = watch(kind, quiet, limit)
    with open(os.path.join(out, kind + ".capture"), "w") as f:
        json.dump({"kind": kind, "root": root, "frames": [base64.b64encode(m).decode() for m in frames]}, f, indent=1)
    print(f"{kind}: {len(frames)} frames, {sum(len(m) for m in frames)} bytes")
send(cbor({"id": rid + 1, "m": "kicad.watch", "p": {"kind": "", "root": root, "path": ""}}))
PY
