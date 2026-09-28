import Base
import ./mockhub.bend as MH
import ../src/core/json.bend as J

# The Apple app's test fixtures (mobile/ios/BackplaneTests/Fixtures): each a
# scene of the mock hub, as the steps that reach it. A step is a frame from
# the hub ({"recv": frame}) or something the user does ({"act": [action,
# value]}). BackplaneTests replays them through the real bridge.js, decodes
# the screens it answers and draws them for the snapshot tests.
# scripts/apple-fixtures.sh writes them; its --check fails when a change to
# the Bend side would change them and they were not written again.

def recv(+o: J.Json) -> J.Json:
  J.Json.obj([J.KV{"recv", o}])

def act(+a: String, +v: String) -> J.Json:
  J.Json.obj([J.KV{"act", J.Json.arr([J.Json.str(a), J.Json.str(v)])}])

def select(+th: String) -> J.Json:
  act("select", MH.Mock.key() ++ "|" ++ th)

def scene(+name: String, +about: String, steps: List<&2, J.Json>) -> String:
  name ++ "\t" ++ J.Json.show(J.Json.obj([J.KV{"about", J.Json.str(about)}, J.KV{"hub", J.Json.str(MH.Mock.key())},
    J.KV{"now", J.Num{Nat.show(MH.Mock.now())}}, J.KV{"steps", J.Json.arr(steps)}]))

def log() -> J.Json:
  recv(MH.Mock.log(MH.Mock.machine()))

def bare() -> MH.MockMachine:
  MH.MockMachine{False{}, False{}, False{}, False{}}

def update() -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("update")}, J.KV{"version", J.Json.str("0.11.0")}, J.KV{"state", J.Json.str("")}])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(scene("projects", "The projects and their threads: running, waiting on a question, finished, failed and settled.", [log()]))
    IO.print(scene("thread-review", "A thread whose turn is running: a review with a table and code, tool calls, a todo list and context usage.", [log(), select("t1")]))
    IO.print(scene("thread-question", "The agent asks three questions (AskUserQuestion), one of them multiple choice.", [log(), select("t2")]))
    IO.print(scene("thread-done", "A finished Codex turn waiting to be read.", [log(), select("t4")]))
    IO.print(scene("thread-failed", "A turn that failed.", [log(), select("t5")]))
    IO.print(scene("settings", "Settings on a machine set up well, after the hub answers the voice status request.", [log(), act("flag", "settings"), recv(MH.Mock.voice(True{}))]))
    IO.print(scene("settings-attention", "Settings that need you: no kicad-cli, no Backplane KiCad, no OpenAI key, and an update waiting.",
      [recv(MH.Mock.log(bare())), act("flag", "settings"), recv(MH.Mock.voice(False{})), recv(update())]))
