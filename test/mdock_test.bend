import Base
import ./check.bend as C
import ./mockhub.bend as MH
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/mobile/hubs.bend as H

# The phones' question dock (src/mobile/dock.bend) on the mock hub's three
# questions (t2, ask k1): what it shows, what each action does, and the one
# request that answers them.

def hub() -> H.Hubs:
  H.Hubs.after(H.Hubs.act(H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(MH.Mock.now(), "c"), [MH.Mock.key()]), MH.Mock.key(), MH.Mock.log(MH.Mock.machine()))),
    "select", MH.Mock.key() ++ "|t2"))

def act(+h: H.Hubs, +a: String, +v: String) -> H.Hubs:
  H.Hubs.after(H.Hubs.act(h, a, v))

def dock(+h: H.Hubs) -> J.Json:
  J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "thread"), "dock")

def q(+h: H.Hubs, +i: Nat) -> J.Json:
  Maybe.default(&2, J.Json, List.get(&2, J.Json, J.Json.elems(J.Json.get_obj(dock(h), "questions")), i), J.Null{})

def ons(os: List<&2, J.Json>) -> String:
  match os:
    case Nil{}:
      ""
    case o <> t:
      Bool.pick(String, J.Json.get_bool(o, "on", False{}), "1", "0") ++ ons(t)

def strs(os: List<&2, J.Json>, +key: String) -> String:
  match os:
    case Nil{}:
      ""
    case o <> t:
      J.Json.get_str(o, key, "") ++ ";" ++ strs(t, key)

def picked(+h: H.Hubs, +i: Nat) -> String:
  ons(J.Json.elems(J.Json.get_obj(q(h, i), "options")))

def labels(+h: H.Hubs, +i: Nat) -> String:
  strs(J.Json.elems(J.Json.get_obj(q(h, i), "options")), "label")

def flag(+o: J.Json, +key: String) -> String:
  Bool.pick(String, J.Json.get_bool(o, key, False{}), "yes", "no")

# what an action sends to the hub: each request's text
def sends(cs: List<&2, H.HCmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case H.HCmd{_, U.Send{+t}} <> r:
      t ++ "\n" ++ sends(r)
    case H.HCmd{_, _} <> r:
      sends(r)

def sent(a: H.HAct) -> String:
  match a:
    case H.HAct{_, cs, _}:
      sends(cs)

def answers(+text: String) -> J.Json:
  J.Json.get_obj(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(String.trim(text)), J.Null{}), "p"), "answers")

# every question answered: the recommended regulator, two rails, the
# inductor where recommended
def ready() -> H.Hubs:
  act(act(hub(), "q-pick", "k1|1|0"), "q-pick", "k1|1|1")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("the dock's ask", J.Json.get_str(dock(hub()), "id", ""), "k1")
    C.Check.str("three questions", Nat.show(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(dock(hub()), "questions")))), "3")
    C.Check.str("the first shown", Nat.show(J.Json.get_nat(dock(hub()), "at", 9n)), "0")
    C.Check.str("labels without the marker", labels(hub(), 0n), "TPS62840;TPS62162;AP62300;")
    C.Check.str("recommended flagged", flag(Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.elems(J.Json.get_obj(q(hub(), 0n), "options"))), J.Null{}), "recommended"), "yes")
    C.Check.str("the recommended one starts picked", picked(hub(), 0n), "100")
    C.Check.str("nothing picked without a recommendation", picked(hub(), 1n), "000")
    C.Check.str("multiple choice", flag(q(hub(), 1n), "multi"), "yes")
    C.Check.str("not ready with a question unanswered", flag(dock(hub()), "ready"), "no")
    # picking
    C.Check.str("a single choice takes one", picked(act(hub(), "q-pick", "k1|0|2"), 0n), "001")
    C.Check.str("a multiple choice toggles", picked(act(act(act(hub(), "q-pick", "k1|1|0"), "q-pick", "k1|1|2"), "q-pick", "k1|1|0"), 1n), "001")
    C.Check.str("ready once each is answered", flag(dock(ready()), "ready"), "yes")
    # own words, and back
    C.Check.str("own words are the answer", J.Json.get_str(q(act(hub(), "q-own", "k1|0|the one we stock"), 0n), "mode", ""), "own")
    C.Check.str("a | in the words is kept", J.Json.get_str(q(act(hub(), "q-own", "k1|0|a|b"), 0n), "own", ""), "a|b")
    C.Check.str("cleared words go back to the pick", J.Json.get_str(q(act(act(act(hub(), "q-pick", "k1|0|2"), "q-own", "k1|0|x"), "q-own", "k1|0|"), 0n), "mode", "") ++ "/" ++ picked(act(act(act(hub(), "q-pick", "k1|0|2"), "q-own", "k1|0|x"), "q-own", "k1|0|"), 0n), "/001")
    C.Check.str("blank words leave the pick", flag(q(act(hub(), "q-own", "k1|0|   "), 0n), "answered"), "yes")
    C.Check.str("a pick drops the words", J.Json.get_str(q(act(act(hub(), "q-own", "k1|0|x"), "q-pick", "k1|0|1"), 0n), "own", "") ++ "/" ++ J.Json.get_str(q(act(act(hub(), "q-own", "k1|0|x"), "q-pick", "k1|0|1"), 0n), "mode", ""), "/")
    C.Check.str("discuss, and back", J.Json.get_str(q(act(hub(), "q-discuss", "k1|1"), 1n), "mode", "") ++ "/" ++ J.Json.get_str(q(act(act(hub(), "q-discuss", "k1|1"), "q-discuss", "k1|1"), 1n), "mode", ""), "discuss/")
    C.Check.str("going to a question", Nat.show(J.Json.get_nat(dock(act(hub(), "q-go", "k1|2")), "at", 9n)), "2")
    C.Check.str("never past the last", Nat.show(J.Json.get_nat(dock(act(hub(), "q-go", "k1|7")), "at", 9n)), "2")
    # sending
    C.Check.str("nothing sent unanswered", sent(H.Hubs.act(hub(), "q-send", "k1")), "")
    C.Check.str("the answers", J.Json.show(answers(sent(H.Hubs.act(ready(), "q-send", "k1")))),
      "{\"Which buck converter should feed the 3V3 rail?\":\"TPS62840\",\"Which rails need a power-good signal to the MCU?\":\"3V3, 1V8\",\"Where should the inductor sit?\":\"Top, beside U7\"}")
    C.Check.str("sent once", sent(H.Hubs.act(act(ready(), "q-send", "k1"), "q-send", "k1")), "")
    C.Check.str("the dock says it went", flag(dock(act(ready(), "q-send", "k1")), "sent"), "yes")
    C.Check.str("discuss is sent as its words", J.Json.get_str(answers(sent(H.Hubs.act(act(ready(), "q-discuss", "k1|2"), "q-send", "k1"))), "Where should the inductor sit?", ""),
      "Let's discuss this before deciding. Explain the trade-offs between the options and wait for my reply.")
