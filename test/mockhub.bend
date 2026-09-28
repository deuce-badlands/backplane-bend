import Base
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J

# A mock hub for the phone and Mac app's tests: the frames a real hub sends
# (a log of its changes, its machine info, an answer to a request), built
# from the model's own changes and encoded by the hub's codec, so they
# cannot drift from what a hub sends. The Swift tests feed these frames to
# bridge.js; test/msettings_test.bend and the others read the screens.
#
# The world is a small hardware shop: two KiCad projects and a tools repo,
# threads in every state the app draws, a bot, and a machine with Claude
# and Codex installed. Every time is fixed, relative to Mock.now().

# the clock the app is started at (2026-09-28 00:00 UTC)
def Mock.now() -> Nat:
  1790553600n

def Mock.ago(+s: Nat) -> Nat:
  Nat.sub(Mock.now(), s)

def Mock.key() -> String:
  "workbench.local:3787"

def Mock.version() -> String:
  "0.10.0"

# The machine info, as Hub.info sends it. The models are a real hub's
# answer (claude 2.1.283, codex-cli 0.157.1), trimmed to a few models.
def Mock.models(+grok: Bool) -> String:
  "{\"claude\":[\"opus\",\"sonnet\",\"haiku\",\"claude-fable-5-1\"],\"codex\":[\"gpt-6-astra\",\"gpt-5.6-luna\"],\"grok\":" ++ Bool.pick(String, grok, "[\"grok-4.7\"]", "[]") ++
  ",\"about\":{\"claude\":{\"cli\":\"2.1.283 (Claude Code)\",\"labels\":{\"default\":\"Default (recommended) · claude-opus-5-5\",\"opus\":\"Opus 5.5 · claude-opus-5-5\",\"sonnet\":\"Sonnet 5 · claude-sonnet-5\",\"haiku\":\"Haiku 4.5 · claude-haiku-4-5-20251001\",\"claude-fable-5-1\":\"Fable 5.1 · For your toughest challenges\"}," ++
  "\"efforts\":{\"default\":[\"low\",\"medium\",\"high\",\"xhigh\",\"max\"],\"opus\":[\"low\",\"medium\",\"high\",\"xhigh\",\"max\"],\"sonnet\":[\"low\",\"medium\",\"high\",\"xhigh\",\"max\"],\"haiku\":null,\"claude-fable-5-1\":[\"low\",\"medium\",\"high\",\"xhigh\",\"max\"]}}," ++
  "\"codex\":{\"cli\":\"codex-cli 0.157.1\",\"labels\":{\"default\":\"Codex's configured default\",\"gpt-6-astra\":\"GPT-6-Astra · Frontier intelligence for the most demanding work.\",\"gpt-5.6-luna\":\"GPT-5.6-Luna · Older fast and efficient model.\"}}," ++
  "\"grok\":{\"cli\":\"" ++ Bool.pick(String, grok, "grok 0.9.2", "") ++ "\",\"labels\":{}}}}"

# the settings screen's facts about the machine: kicad-cli found or not, the
# Backplane KiCad fork or not, updated by a package or from releases
type MockMachine is Data:
  MockMachine{kicad: Bool, fork: Bool, package: Bool, grok: Bool}

def Mock.machine() -> MockMachine:
  MockMachine{True{}, True{}, False{}, False{}}

def Mock.info(m: MockMachine) -> J.Json:
  match m:
    case MockMachine{kicad, fork, package, grok}:
      J.Json.obj([J.KV{"home", J.Json.str("/home/ada/.backplane")}, J.KV{"listen", J.Json.str("0.0.0.0:3787")},
        J.KV{"models", J.Json.str(Mock.models(grok))},
        J.KV{"machines", J.Json.str("{\"self\":{\"name\":\"workbench\",\"url\":\"http://100.64.0.7:3787\",\"domain\":\"workbench.tail2f3e.ts.net\"},\"peers\":[]}")},
        J.KV{"tailnet", J.Json.str("on")}, J.KV{"update", J.Json.str(Bool.pick(String, package, "package", "releases"))},
        J.KV{"pair", J.Json.str("backplane://pair?url=http%3A%2F%2F100.64.0.7%3A3787&token=7f3a9c21e5")},
        J.KV{"kicad.cli", J.Json.str(Bool.pick(String, kicad, "/usr/bin/kicad-cli", ""))},
        J.KV{"kicad.fork", J.Json.str(Bool.pick(String, fork, "10.0.6-bp3", ""))}, J.KV{"kicad.commit", J.Json.str("")}])

# The projects, threads and their history
# -----------------------------------------

def Mock.t(+id: String, +project: String, +title: String, +provider: String, +model: String, +at: Nat) -> M.Change:
  M.ThreadCreated{id, project, title, M.Worktree{}, "backplane/" ++ id, "/home/ada/.backplane/worktrees/" ++ id, provider, model, at}

def Mock.user(+th: String, +msg: String, +text: String, +at: Nat) -> M.Change:
  M.MessagePosted{th, msg, M.User{}, text, at}

def Mock.agent(+th: String, +msg: String, +text: String, +at: Nat) -> M.Change:
  M.MessagePosted{th, msg, M.Assistant{}, text, at}

def Mock.tool(+th: String, +id: String, +name: String, +summary: String, +at: Nat) -> M.Change:
  M.ActivityLogged{th, id, "tool", name, summary, at}

# the IMU thread: a finished review with a table, code, tools and a plan
def Mock.review() -> String:
  "The SPI bus to the IMU is routable on two layers, but two nets break the length budget.\n\n" ++
  "## Length check\n\n" ++
  "| Net | Length | Budget | Status |\n|---|---:|---:|---|\n" ++
  "| IMU_SCK | 41.2 mm | 45 mm | ok |\n| IMU_MOSI | 47.9 mm | 45 mm | over |\n| IMU_MISO | 46.3 mm | 45 mm | over |\n| IMU_CS | 38.0 mm | 45 mm | ok |\n\n" ++
  "MOSI and MISO detour around the **USB-C connector**. Moving `U4` 3 mm toward the MCU brings both under budget without new vias.\n\n" ++
  "```python\n# resources/check_spi_lengths.py\nBUDGET_MM = 45.0\nover = [n for n, mm in lengths.items() if mm > BUDGET_MM]\n```\n\n" ++
  "Next:\n\n- Move `U4` and rerun DRC.\n- Add series 22 Ω resistors on SCK if ringing shows on the scope."

def Mock.todos() -> String:
  "[{\"id\":\"1\",\"text\":\"Measure the SPI net lengths\",\"form\":\"Measuring the SPI net lengths\",\"status\":\"completed\"}," ++
  "{\"id\":\"2\",\"text\":\"Move U4 toward the MCU\",\"form\":\"Moving U4 toward the MCU\",\"status\":\"in_progress\"}," ++
  "{\"id\":\"3\",\"text\":\"Rerun DRC with schematic parity\",\"form\":\"Rerunning DRC\",\"status\":\"pending\"}]"

# the buck converter thread: the agent asks three questions (AskUserQuestion)
def Mock.questions() -> String:
  "[{\"question\":\"Which buck converter should feed the 3V3 rail?\",\"header\":\"Regulator\",\"multiSelect\":false,\"options\":[" ++
  "{\"label\":\"TPS62840 (Recommended)\",\"description\":\"60 nA quiescent, 750 mA. Best for the sleep budget.\"}," ++
  "{\"label\":\"TPS62162\",\"description\":\"1 A, cheaper, but 17 µA quiescent.\"}," ++
  "{\"label\":\"AP62300\",\"description\":\"3 A headroom; larger inductor and more board area.\"}]}," ++
  "{\"question\":\"Which rails need a power-good signal to the MCU?\",\"header\":\"Power good\",\"multiSelect\":true,\"options\":[" ++
  "{\"label\":\"3V3\",\"description\":\"The MCU's own rail.\"},{\"label\":\"1V8\",\"description\":\"The IMU's I/O rail.\"},{\"label\":\"5V USB\",\"description\":\"VBUS after the load switch.\"}]}," ++
  "{\"question\":\"Where should the inductor sit?\",\"header\":\"Placement\",\"multiSelect\":false,\"options\":[" ++
  "{\"label\":\"Top, beside U7 (Recommended)\",\"description\":\"Shortest switch node; keeps the bottom clear for the battery.\"}," ++
  "{\"label\":\"Bottom, under U7\",\"description\":\"Saves area but puts the switch node under the IMU.\"}]}]"

def Mock.log.changes() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "sensor-hub", "/home/ada/boards/sensor-hub/v2", Mock.ago(864000n)},
   M.ProjectCreated{"p2", "usb-pd-sink", "/home/ada/boards/usb-pd-sink/v1", Mock.ago(700000n)},
   M.ProjectCreated{"p3", "bench-tools", "/home/ada/src/bench-tools", Mock.ago(600000n)},
   # sensor-hub: a turn running, a question waiting, one settled
   Mock.t("t1", "p1", "Route the IMU's SPI bus", "claude", "opus", Mock.ago(5400n)),
   Mock.user("t1", "m1", "Check the SPI lengths to the IMU against the 45 mm budget and tell me what breaks it.", Mock.ago(5300n)),
   Mock.tool("t1", "a1", "Read", "sensor-hub_v2.kicad_pcb", Mock.ago(5280n)),
   Mock.tool("t1", "a2", "Bash", "python3 resources/check_spi_lengths.py", Mock.ago(5260n)),
   Mock.tool("t1", "a3", "Grep", "IMU_ in sensor-hub_v2.kicad_sch", Mock.ago(5250n)),
   Mock.agent("t1", "m2", Mock.review(), Mock.ago(5200n)),
   M.TurnChanged{"t1", M.Completed{}, Mock.ago(5190n)},
   Mock.user("t1", "m3", "Move U4 and rerun DRC.", Mock.ago(300n)),
   Mock.tool("t1", "a4", "Edit", "sensor-hub_v2.kicad_pcb", Mock.ago(240n)),
   M.TodosSet{"t1", Mock.todos(), Mock.ago(230n)},
   M.UsageSet{"t1", 184000n, 1000000n, Mock.ago(220n)},
   M.TurnChanged{"t1", M.Running{}, Mock.ago(290n)},
   Mock.t("t2", "p1", "Pick a buck converter for 3V3", "claude", "opus", Mock.ago(1800n)),
   Mock.user("t2", "m4", "Pick the 3V3 regulator. Battery life matters more than cost.", Mock.ago(1700n)),
   Mock.tool("t2", "a5", "WebFetch", "ti.com/product/TPS62840", Mock.ago(1650n)),
   Mock.agent("t2", "m5", "Three parts fit the 3V3 rail. Before I place one I need three decisions from you.", Mock.ago(1600n)),
   M.AskOpened{"k1", "t2", "input", "AskUserQuestion", "Which buck converter should feed the 3V3 rail?", "TPS62840 (Recommended)\nTPS62162\nAP62300", Mock.questions(), Mock.ago(1590n)},
   Mock.t("t3", "p1", "Fix silkscreen over pads", "codex", "gpt-6-astra", Mock.ago(400000n)),
   Mock.agent("t3", "m6", "Moved 14 reference designators off pads; DRC is clean.", Mock.ago(399000n)),
   M.TurnChanged{"t3", M.Completed{}, Mock.ago(398990n)},
   M.ThreadSettled{"t3", False{}, Mock.ago(300000n)},
   # usb-pd-sink: finished work waiting to be read, and a failed turn
   Mock.t("t4", "p2", "Review the PD negotiation schematic", "codex", "gpt-6-astra", Mock.ago(7200n)),
   Mock.user("t4", "m7", "Review the TPS25751 configuration for a 20 V / 3 A sink.", Mock.ago(7100n)),
   Mock.agent("t4", "m8", "The PDO table asks for 20 V at 3 A, but R12 sets the current limit to 2.25 A. Change R12 to 6.04 kΩ.", Mock.ago(6900n)),
   M.TurnChanged{"t4", M.Completed{}, Mock.ago(6890n)},
   Mock.t("t5", "p2", "Export the JLCPCB order", "claude", "sonnet", Mock.ago(90000n)),
   Mock.agent("t5", "m9", "export.sh stopped: kicad-cli could not open the 3D model for J1.", Mock.ago(89000n)),
   M.TurnChanged{"t5", M.Failed{}, Mock.ago(88990n)},
   # bench-tools: a quiet thread
   Mock.t("t6", "p3", "Add a --json flag to the bench report", "claude", "sonnet", Mock.ago(200000n)),
   M.TurnChanged{"t6", M.Completed{}, Mock.ago(199000n)},
   # settings a user has chosen
   M.SettingSet{"agent.provider", "claude", Mock.ago(864000n)},
   M.SettingSet{"agent.model", "opus", Mock.ago(864000n)},
   M.SettingSet{"settle.days", "5", Mock.ago(864000n)},
   M.SettingSet{"followup", "steer", Mock.ago(864000n)},
   M.SettingSet{"ui.theme", "dark", Mock.ago(864000n)},
   # a bot
   M.BotSet{"b1", "Librarian", "tb1", 2n, "Finds datasheets and keeps the parts library tidy.", Mock.ago(500000n)}]

def Mock.items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> Mock.items(t)

# the hub's first frame: its whole log, its version and its machine info
def Mock.log(m: MockMachine) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"items", J.Json.arr(Mock.items(Mock.log.changes()))},
    J.KV{"version", J.Json.str(Mock.version())}, J.KV{"origin", J.Json.str("o1")}, J.KV{"info", Mock.info(m)}])

# the hub's answer to Settings' voice status request: a saved key (masked),
# the dictionary, and the machine's microphones
def Mock.voice(key: Bool) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("reply")}, J.KV{"id", J.Json.str("")}, J.KV{"ok", J.Json.bool(True{})},
    J.KV{"voiceKey", J.Json.str(Bool.pick(String, key, "sk-…9f2c", ""))}, J.KV{"voiceDict", J.Json.str("TPS62840\nKiCad\nJLCPCB")},
    J.KV{"voiceDevices", J.Json.str("{\"event\":\"devices\",\"default\":\"alsa_input.usb-Blue_Yeti\",\"devices\":[{\"name\":\"alsa_input.usb-Blue_Yeti\",\"label\":\"Blue Yeti\"},{\"name\":\"alsa_input.pci-0000_00_1f.3\",\"label\":\"Built-in Audio\"}]}")}])

# a frame of new changes, as the hub broadcasts one when its state moves
def Mock.changes(cs: List<&2, M.Change>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("changes")}, J.KV{"items", J.Json.arr(Mock.items(cs))}])
