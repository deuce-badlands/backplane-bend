import Base
import ./check.bend as C
import ./mockhub.bend as MH
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/mobile/hubs.bend as H

# The apps' Settings (src/mobile/screen.bend Mob.settings): the sections in
# the native window's order with what each has set and whether it needs
# you, and each row's control, value and actions, against the mock hub.

def hub(m: MH.MockMachine) -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(MH.Mock.now(), "c"), [MH.Mock.key()]), MH.Mock.key(), MH.Mock.log(m)))

def recv(+h: H.Hubs, +o: J.Json) -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(h, MH.Mock.key(), o))

def act(+h: H.Hubs, +a: String, +v: String) -> H.Hubs:
  H.Hubs.after(H.Hubs.act(h, a, v))

# Settings open on a machine, before and after the hub answers the voice
# status request opening them sends
def opened(m: MH.MockMachine) -> H.Hubs:
  act(hub(m), "flag", "settings")

def answered(m: MH.MockMachine, key: Bool) -> H.Hubs:
  recv(opened(m), MH.Mock.voice(key))

def settings(+h: H.Hubs) -> J.Json:
  J.Json.get_obj(H.Hubs.screen(h), "settings")

def strs(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      J.Json.get_str(j, key, "") ++ ";" ++ strs(t, key)

def flags(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      Bool.pick(String, J.Json.get_bool(j, key, False{}), "1", "0") ++ flags(t, key)

def sections(+h: H.Hubs, +key: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(settings(h), "sections")), key)

def attention(+h: H.Hubs) -> String:
  flags(J.Json.elems(J.Json.get_obj(settings(h), "sections")), "attention")

def rows(+h: H.Hubs, +key: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(settings(h), "rows")), key)

def find(js: List<&2, J.Json>, +label: String) -> J.Json:
  match js:
    case Nil{}:
      J.Null{}
    case +j <> t:
      Bool.pick(J.Json, String.eq(J.Json.get_str(j, "label", ""), label), j, find(t, label))

def row(+h: H.Hubs, +label: String) -> J.Json:
  find(J.Json.elems(J.Json.get_obj(settings(h), "rows")), label)

def get(+h: H.Hubs, +label: String, +key: String) -> String:
  J.Json.get_str(row(h, label), key, "")

def buttons(+h: H.Hubs, +label: String, +key: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(row(h, label), "buttons")), key)

def chips(+h: H.Hubs, +label: String, +key: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(row(h, label), "chips")), key)

def on(+h: H.Hubs, +label: String) -> String:
  flags(J.Json.elems(J.Json.get_obj(row(h, label), "buttons")), "on")

def field(+h: H.Hubs, +label: String, +key: String) -> String:
  J.Json.get_str(J.Json.get_obj(row(h, label), "field"), key, "")

def secret(+h: H.Hubs, +label: String) -> String:
  Bool.pick(String, J.Json.get_bool(J.Json.get_obj(row(h, label), "field"), "secret", False{}), "secret", "plain")

def closed.k(s: J.Json) -> String:
  match s:
    case J.Null{}:
      "closed"
    case _:
      "open"

def closed(+h: H.Hubs) -> String:
  closed.k(settings(h))

# the hub confirming a setting (what a "setting" action asks it for)
def set(+h: H.Hubs, +k: String, +v: String) -> H.Hubs:
  recv(h, MH.Mock.changes([M.SettingSet{k, v, MH.Mock.now()}]))

# where an action's commands go: "send@<hub>" for each request
def cmds(cs: List<&2, H.HCmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case H.HCmd{k, U.Send{_}} <> t:
      "send@" ++ k ++ " " ++ cmds(t)
    case H.HCmd{_, _} <> t:
      cmds(t)

def sent(a: H.HAct) -> String:
  match a:
    case H.HAct{_, cs, _}:
      cmds(cs)

def good() -> MH.MockMachine:
  MH.Mock.machine()

def bare() -> MH.MockMachine:
  MH.MockMachine{False{}, False{}, False{}, False{}}

def packaged() -> MH.MockMachine:
  MH.MockMachine{True{}, True{}, True{}, True{}}

# a new release offered while Settings is open
def update() -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("update")}, J.KV{"version", J.Json.str("0.11.0")}, J.KV{"state", J.Json.str("")}])

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("closed until flagged", closed(hub(good())), "closed")
    C.Check.str("flag opens", closed(opened(good())), "open")
    C.Check.str("flag again closes", closed(act(opened(good()), "flag", "settings")), "closed")
    # the sections, in the native window's order, with what each has set
    C.Check.str("sections", sections(answered(good(), True{}), "title"), "Threads;Agents;Writing;KiCad;Appearance;Network;Voice;")
    C.Check.str("summaries", sections(answered(good(), True{}), "summary"),
      "Settle 5 days · Steer;Claude · Opus 5.5;Claude · Haiku 4.5;Found;Dark;Stable;Key saved;")
    C.Check.str("nothing needs you", attention(answered(good(), True{})), "0000000")
    C.Check.str("no key needs you", attention(answered(good(), False{})), "0000001")
    C.Check.str("before the hub answers, no key", sections(opened(good()), "summary"),
      "Settle 5 days · Steer;Claude · Opus 5.5;Claude · Haiku 4.5;Found;Dark;Stable;No key;")
    C.Check.str("no kicad-cli needs you", attention(answered(bare(), True{})), "0001000")
    C.Check.str("an update needs you", attention(recv(answered(good(), True{}), update())), "0000010")
    C.Check.str("an update in the summary", sections(recv(answered(good(), True{}), update()), "summary"),
      "Settle 5 days · Steer;Claude · Opus 5.5;Claude · Haiku 4.5;Found;Dark;Stable · update;Key saved;")
    # every row: its section and the control it is
    C.Check.str("rows", rows(answered(good(), True{}), "label"),
      "Settle after;Follow-ups while a turn runs;Provider for new threads;Model for new threads;Claude Code;Codex;Grok;Provider;Model;KiCad CLI;KiCad IPC;Theme;Tailscale;Pairing link;Update channel;Backplane 0.10.0;OpenAI API key;Microphone;Dictionary;")
    C.Check.str("row sections", rows(answered(good(), True{}), "section"),
      "Threads;Threads;Agents;Agents;Agents;Agents;Agents;Writing;Writing;KiCad;KiCad;Appearance;Network;Network;Network;Network;Voice;Voice;Voice;")
    C.Check.str("kinds", rows(answered(good(), True{}), "kind"),
      "stepper;choice;choice;menu;status;status;status;choice;menu;status;switch;choice;status;status;choice;status;field;menu;field;")
    C.Check.str("only the CLIs are grouped", rows(answered(good(), True{}), "group"), ";;;;Installed;Installed;Installed;;;;;;;;;;;;;")
    # Threads
    C.Check.str("stepper value", get(answered(good(), True{}), "Settle after", "value"), "5 days")
    C.Check.str("stepper steps", buttons(answered(good(), True{}), "Settle after", "value"), "settle.days=4;settle.days=6;")
    C.Check.str("follow-ups", buttons(answered(good(), True{}), "Follow-ups while a turn runs", "label"), "Default;Queue;Steer;")
    C.Check.str("follow-up chosen", on(answered(good(), True{}), "Follow-ups while a turn runs"), "001")
    C.Check.str("follow-up values", buttons(answered(good(), True{}), "Follow-ups while a turn runs", "value"), "followup=;followup=queue;followup=steer;")
    # Agents
    C.Check.str("providers", buttons(answered(good(), True{}), "Provider for new threads", "label"), "Claude;Codex;Grok;")
    C.Check.str("model menu", buttons(answered(good(), True{}), "Model for new threads", "label"), "Default (recommended);Opus 5.5;Sonnet 5;Haiku 4.5;Fable 5.1;")
    C.Check.str("model chosen", on(answered(good(), True{}), "Model for new threads"), "01000")
    C.Check.str("model note", get(answered(good(), True{}), "Model for new threads", "note"), "Opus 5.5 · claude-opus-5-5")
    C.Check.str("claude installed", get(answered(good(), True{}), "Claude Code", "value") ++ "/" ++ get(answered(good(), True{}), "Claude Code", "tone"), "2.1.283 (Claude Code)/ok")
    C.Check.str("codex installed", get(answered(good(), True{}), "Codex", "value"), "codex-cli 0.157.1")
    C.Check.str("grok missing", get(answered(good(), True{}), "Grok", "value") ++ "/" ++ get(answered(good(), True{}), "Grok", "tone"), "Not installed/")
    C.Check.str("grok installed", get(answered(packaged(), True{}), "Grok", "value"), "grok 0.9.2")
    # Writing: the provider's light model unless set
    C.Check.str("writing model", on(answered(good(), True{}), "Model"), "00010")
    C.Check.str("a setting asks the hub", sent(H.Hubs.act(answered(good(), True{}), "setting", "text.model=sonnet")), "send@workbench.local:3787 ")
    C.Check.str("writing model set", on(set(answered(good(), True{}), "text.model", "sonnet"), "Model"), "00100")
    C.Check.str("opening asks for voice status", sent(H.Hubs.act(hub(good()), "flag", "settings")), "send@workbench.local:3787 ")
    # KiCad
    C.Check.str("kicad found", get(answered(good(), True{}), "KiCad CLI", "value") ++ "/" ++ get(answered(good(), True{}), "KiCad CLI", "tone"), "Found/ok")
    C.Check.str("kicad missing", get(answered(bare(), True{}), "KiCad CLI", "value") ++ "/" ++ get(answered(bare(), True{}), "KiCad CLI", "tone"), "Not found/warn")
    C.Check.str("ipc switch", buttons(answered(good(), True{}), "KiCad IPC", "label"), "On;Off;")
    C.Check.str("ipc on", on(answered(good(), True{}), "KiCad IPC"), "10")
    C.Check.str("ipc turned off", on(set(answered(good(), True{}), "kicad.ipc", "off"), "KiCad IPC"), "01")
    C.Check.str("ipc without the fork", get(answered(bare(), True{}), "KiCad IPC", "kind") ++ "/" ++ buttons(answered(bare(), True{}), "KiCad IPC", "action"), "status/kicad-install;")
    # Appearance
    C.Check.str("themes", buttons(answered(good(), True{}), "Theme", "label"), "System;Dark;Light;")
    C.Check.str("theme chosen", on(answered(good(), True{}), "Theme"), "010")
    # Network
    C.Check.str("tailscale", get(answered(good(), True{}), "Tailscale", "value"), "on")
    C.Check.str("pairing copies", buttons(answered(good(), True{}), "Pairing link", "action"), "copy;")
    C.Check.str("up to date", get(answered(good(), True{}), "Backplane 0.10.0", "value") ++ "/" ++ buttons(answered(good(), True{}), "Backplane 0.10.0", "action"), "Current/update-check;")
    C.Check.str("update ready", get(recv(answered(good(), True{}), update()), "Backplane 0.10.0", "value") ++ "/" ++ buttons(recv(answered(good(), True{}), update()), "Backplane 0.10.0", "action"), "Update ready/update;")
    C.Check.str("packaged", get(answered(packaged(), True{}), "Backplane 0.10.0", "value") ++ "/" ++ buttons(answered(packaged(), True{}), "Backplane 0.10.0", "action"), "Package/")
    # Voice: typed fields, and the actions that read them
    C.Check.str("key field", field(answered(good(), False{}), "OpenAI API key", "name") ++ "/" ++ secret(answered(good(), False{}), "OpenAI API key"), "vkey/secret")
    C.Check.str("key buttons, none saved", buttons(answered(good(), False{}), "OpenAI API key", "action"), "voice-key;")
    C.Check.str("key buttons, one saved", buttons(answered(good(), True{}), "OpenAI API key", "action"), "voice-key;voice-unkey;")
    C.Check.str("key shown masked", get(answered(good(), True{}), "OpenAI API key", "value"), "sk-…9f2c")
    C.Check.str("typed key kept", field(act(answered(good(), False{}), "bfield", "vkey\u{1f}sk-new"), "OpenAI API key", "text"), "sk-new")
    C.Check.str("microphones", buttons(answered(good(), True{}), "Microphone", "label"), "Default;Blue Yeti;Built-in Audio;")
    C.Check.str("microphone chosen", on(answered(good(), True{}), "Microphone"), "100")
    C.Check.str("default microphone named", get(answered(good(), True{}), "Microphone", "note"), "The composer's mic records the hub machine's default microphone, Blue Yeti.")
    C.Check.str("no microphones listed", get(opened(good()), "Microphone", "note"), "The composer's mic records the hub machine's default microphone.")
    C.Check.str("dictionary field", field(answered(good(), True{}), "Dictionary", "name") ++ "/" ++ secret(answered(good(), True{}), "Dictionary"), "vterm/plain")
    C.Check.str("dictionary add", buttons(answered(good(), True{}), "Dictionary", "action"), "voice-term;")
    C.Check.str("dictionary terms", chips(answered(good(), True{}), "Dictionary", "label"), "TPS62840;KiCad;JLCPCB;")
    C.Check.str("a term's chip takes it out", chips(answered(good(), True{}), "Dictionary", "action"), "voice-unterm;voice-unterm;voice-unterm;")
