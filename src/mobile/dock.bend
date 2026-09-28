import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U

# The phones' question dock: an agent's questions (AskUserQuestion) where
# the composer was, one at a time. Everything it shows and sends is
# decided here; the app draws the "dock" of the thread's screen and sends
# its actions:
#   q-pick   "ask|i|o"     option o of question i (a multiple choice
#                          question toggles it); drops words typed there
#   q-own    "ask|i|text"  the question's answer in the person's own words
#                          (empty: back to the options picked)
#   q-discuss "ask|i"      talk it through first (again: back)
#   q-go     "ask|i"       show question i
#   q-send   "ask"         every question answered: the answers go to the
#                          hub as one map (question -> answer), once
# Nothing is picked until the person picks, except the option Claude marks
# "(Recommended)", which starts picked. The marker is not part of the
# label shown or the answer sent.

def MDock.mark() -> String:
  "(Recommended)"

# the text without the marker, wherever it is
def MDock.cut(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, +t}:
      Bool.pick(String, String.starts_with(SCon{h, t}, MDock.mark()), String.drop(SCon{h, t}, 13n), SCon{h, MDock.cut(t)})

def MDock.label(+s: String) -> String:
  String.trim(MDock.cut(s))

def MDock.rec(+s: String) -> Bool:
  String.contains(s, MDock.mark())

# what the person answers "Discuss this" with
def MDock.discuss() -> String:
  "Let's discuss this before deciding. Explain the trade-offs between the options and wait for my reply."

# the ask's questions, as Claude sent them
def MDock.qs(+qs: String) -> List<&2, J.Json>:
  J.Json.elems(Maybe.default(&2, J.Json, Bool.pick(Maybe<&2, J.Json>, String.is_empty(qs), None{}, J.Json.parse(qs)), J.Null{}))

def MDock.opts(+q: J.Json) -> List<&2, J.Json>:
  J.Json.elems(J.Json.get_obj(q, "options"))

def MDock.multi(+q: J.Json) -> Bool:
  J.Json.get_bool(q, "multiSelect", False{})

# the recommended option's index (the first so marked)
def MDock.first.go(os: List<&2, J.Json>, +i: Nat) -> Maybe<&2, Nat>:
  match os:
    case Nil{}:
      None{}
    case +o <> t:
      Bool.pick(Maybe<&2, Nat>, MDock.rec(J.Json.get_str(o, "label", "")), Some{i}, MDock.first.go(t, 1n+i))

def MDock.first.k(m: Maybe<&2, Nat>) -> List<&2, Nat>:
  match m:
    case Some{i}:
      [i]
    case None{}:
      Nil{}

def MDock.first(+q: J.Json) -> List<&2, Nat>:
  MDock.first.k(MDock.first.go(MDock.opts(q), 0n))

# The dock's state, in the client's scratch: per question its picks
# ("0,2"; unset until touched: the recommended one), words of its own, and
# its mode ("" the options, "own", "discuss"); the question shown, and
# whether the answers went
def MDock.key(+ask: String, +i: Nat, +f: String) -> String:
  "@q." ++ ask ++ "." ++ Nat.show(i) ++ "." ++ f

def MDock.at.key(+ask: String) -> String:
  "@q." ++ ask ++ ".at"

def MDock.sent.key(+ask: String) -> String:
  "@q." ++ ask ++ ".sent"

def MDock.nat.put(m: Maybe<&2, Nat>, rest: List<&2, Nat>) -> List<&2, Nat>:
  match m:
    case Some{n}:
      n <> rest
    case None{}:
      rest

def MDock.nats(ss: List<&2, String>) -> List<&2, Nat>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      MDock.nat.put(Nat.read(String.trim(s)), MDock.nats(t))

def MDock.show(ns: List<&2, Nat>) -> String:
  match ns:
    case Nil{}:
      ""
    case n <> Nil{}:
      Nat.show(n)
    case n <> t:
      Nat.show(n) ++ "," ++ MDock.show(t)

def MDock.has(ns: List<&2, Nat>, +n: Nat) -> Bool:
  match ns:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(Nat.is_eq(h, n), MDock.has(t, n))

def MDock.without(ns: List<&2, Nat>, +n: Nat) -> List<&2, Nat>:
  match ns:
    case Nil{}:
      Nil{}
    case +h <> t:
      MDock.nat.put(Bool.pick(Maybe<&2, Nat>, Nat.is_eq(h, n), None{}, Some{h}), MDock.without(t, n))

def MDock.picks(+u: U.Ui, +ask: String, +i: Nat, +q: J.Json) -> List<&2, Nat>:
  Bool.pick(List<&2, Nat>, String.is_empty(U.Ui.scratch(u, MDock.key(ask, i, "t"))), MDock.first(q),
    MDock.nats(String.split(U.Ui.scratch(u, MDock.key(ask, i, "p")), ',')))

def MDock.own(+u: U.Ui, +ask: String, +i: Nat) -> String:
  U.Ui.scratch(u, MDock.key(ask, i, "own"))

def MDock.mode(+u: U.Ui, +ask: String, +i: Nat) -> String:
  U.Ui.scratch(u, MDock.key(ask, i, "m"))

# The answer to one question, as Claude reads it: the picked options'
# labels in the options' order (without the marker), the words typed, or
# the ask to discuss
def MDock.label.put(on: Bool, +label: String, rest: List<&2, String>) -> List<&2, String>:
  match on:
    case True{}:
      MDock.label(label) <> rest
    case False{}:
      rest

def MDock.labels(os: List<&2, J.Json>, +i: Nat, +picks: List<&2, Nat>) -> List<&2, String>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      MDock.label.put(MDock.has(picks, i), J.Json.get_str(o, "label", ""), MDock.labels(t, 1n+i, picks))

def MDock.answer(+q: J.Json, +picks: List<&2, Nat>, +own: String, +mode: String) -> String:
  Bool.pick(String, String.eq(mode, "discuss"), MDock.discuss(),
    Bool.pick(String, String.eq(mode, "own"), String.trim(own), String.join(MDock.labels(MDock.opts(q), 0n, picks), ", ")))

def MDock.answered(+picks: List<&2, Nat>, +own: String, +mode: String) -> Bool:
  Bool.pick(Bool, String.eq(mode, "discuss"), True{},
    Bool.pick(Bool, String.eq(mode, "own"), Bool.not(String.is_empty(String.trim(own))), Bool.not(List.is_empty(&2, Nat, picks))))

# The open ask a thread's dock shows: the first with questions
def MDock.find(as: List<&2, M.Ask>) -> Maybe<&2, M.Ask>:
  match as:
    case Nil{}:
      None{}
    case M.Ask{+i, +th, +k, +tool, +d, +o, +qs, +op, +an} <> t:
      Bool.pick(Maybe<&2, M.Ask>, List.is_empty(&2, J.Json, MDock.qs(qs)), MDock.find(t), Some{M.Ask{i, th, k, tool, d, o, qs, op, an}})

# an ask by its id, among the open ones
def MDock.by.go(as: List<&2, M.Ask>, +ask: String) -> String:
  match as:
    case Nil{}:
      ""
    case M.Ask{+i, _, _, _, _, _, +qs, _, _} <> t:
      Bool.pick(String, String.eq(i, ask), qs, MDock.by.go(t, ask))

def MDock.by(+u: U.Ui, +ask: String) -> List<&2, J.Json>:
  MDock.qs(MDock.by.go(M.Asks.all(U.Ui.state.of(u)), ask))

def MDock.nth(qs: List<&2, J.Json>, +i: Nat) -> J.Json:
  Maybe.default(&2, J.Json, List.get(&2, J.Json, qs, i), J.Null{})

# every question answered?
def MDock.all.go(qs: List<&2, J.Json>, +u: U.Ui, +ask: String, +i: Nat) -> Bool:
  match qs:
    case Nil{}:
      True{}
    case +q <> t:
      Bool.and(MDock.answered(MDock.picks(u, ask, i, q), MDock.own(u, ask, i), MDock.mode(u, ask, i)), MDock.all.go(t, u, ask, 1n+i))

# the answers map: question text -> answer
def MDock.map.go(qs: List<&2, J.Json>, +u: U.Ui, +ask: String, +i: Nat) -> List<&2, J.KV>:
  match qs:
    case Nil{}:
      Nil{}
    case +q <> t:
      J.KV{J.Json.get_str(q, "question", ""), J.Json.str(MDock.answer(q, MDock.picks(u, ask, i, q), MDock.own(u, ask, i), MDock.mode(u, ask, i)))} <> MDock.map.go(t, u, ask, 1n+i)

# The actions
# -----------

def MDock.args(+v: String) -> List<&2, String>:
  String.split(v, '|')

def MDock.arg(+v: String, +n: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, MDock.args(v), n), "")

def MDock.idx(+v: String, +n: Nat) -> Nat:
  Maybe.default(&2, Nat, Nat.read(MDock.arg(v, n)), 0n)

# "ask|i|o": a single choice takes o; a multiple choice turns o on or off
def MDock.pick.set(multi: Bool, +was: List<&2, Nat>, +o: Nat) -> List<&2, Nat>:
  match multi:
    case True{}:
      Bool.pick(List<&2, Nat>, MDock.has(was, o), MDock.without(was, o), List.append(&2, Nat, was, [o]))
    case False{}:
      [o]

def MDock.pick.k(+u: U.Ui, +ask: String, +i: Nat, +o: Nat, +q: J.Json) -> U.Act:
  U.Act{U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(u,
    MDock.key(ask, i, "p"), MDock.show(MDock.pick.set(MDock.multi(q), MDock.picks(u, ask, i, q), o))), MDock.key(ask, i, "t"), "1"),
    MDock.key(ask, i, "m"), ""), MDock.key(ask, i, "own"), ""), Nil{}}

def MDock.pick(+u: U.Ui, +v: String) -> U.Act:
  MDock.pick.k(u, MDock.arg(v, 0n), MDock.idx(v, 1n), MDock.idx(v, 2n), MDock.nth(MDock.by(u, MDock.arg(v, 0n)), MDock.idx(v, 1n)))

# "ask|i|text": the words (a '|' in them kept); empty goes back to the picks
def MDock.own.text(+v: String) -> String:
  String.join(List.drop(&2, String, MDock.args(v), 2n), "|")

def MDock.own.set(+u: U.Ui, +ask: String, +i: Nat, +text: String) -> U.Act:
  U.Act{U.Ui.scratch_set(U.Ui.scratch_set(u, MDock.key(ask, i, "own"), text), MDock.key(ask, i, "m"),
    Bool.pick(String, String.is_empty(String.trim(text)), "", "own")), Nil{}}

def MDock.own.act(+u: U.Ui, +v: String) -> U.Act:
  MDock.own.set(u, MDock.arg(v, 0n), MDock.idx(v, 1n), MDock.own.text(v))

def MDock.discuss.act(+u: U.Ui, +v: String) -> U.Act:
  U.Act{U.Ui.scratch_set(u, MDock.key(MDock.arg(v, 0n), MDock.idx(v, 1n), "m"),
    Bool.pick(String, String.eq(MDock.mode(u, MDock.arg(v, 0n), MDock.idx(v, 1n)), "discuss"), "", "discuss")), Nil{}}

def MDock.go(+u: U.Ui, +v: String) -> U.Act:
  U.Act{U.Ui.scratch_set(u, MDock.at.key(MDock.arg(v, 0n)), Nat.show(MDock.idx(v, 1n))), Nil{}}

# "ask": sent once, and only with every question answered
def MDock.send.k(go: Bool, +u: U.Ui, +ask: String, qs: List<&2, J.Json>) -> U.Act:
  match go:
    case True{}:
      U.Ui.rpc.keep(U.Ui.scratch_set(u, MDock.sent.key(ask), "1"), "ask.answer",
        [J.KV{"id", J.Str{ask}}, J.KV{"answers", J.Json.obj(MDock.map.go(qs, u, ask, 0n))}])
    case False{}:
      U.Act{u, Nil{}}

def MDock.send(+u: U.Ui, +ask: String) -> U.Act:
  +qs = MDock.by(u, ask)
  MDock.send.k(Bool.and(Bool.not(List.is_empty(&2, J.Json, qs)), Bool.and(String.is_empty(U.Ui.scratch(u, MDock.sent.key(ask))), MDock.all.go(qs, u, ask, 0n))), u, ask, qs)

# The dock, as the app draws it
# -----------------------------

def MDock.opt.json(os: List<&2, J.Json>, +i: Nat, +picks: List<&2, Nat>) -> List<&2, J.Json>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.Json.obj([J.KV{"label", J.Json.str(MDock.label(J.Json.get_str(o, "label", "")))}, J.KV{"description", J.Json.str(J.Json.get_str(o, "description", ""))},
        J.KV{"recommended", J.Json.bool(MDock.rec(J.Json.get_str(o, "label", "")))}, J.KV{"on", J.Json.bool(MDock.has(picks, i))}]) <> MDock.opt.json(t, 1n+i, picks)

def MDock.q.json(+q: J.Json, +picks: List<&2, Nat>, +own: String, +mode: String) -> J.Json:
  J.Json.obj([J.KV{"question", J.Json.str(J.Json.get_str(q, "question", ""))}, J.KV{"header", J.Json.str(J.Json.get_str(q, "header", ""))},
    J.KV{"multi", J.Json.bool(MDock.multi(q))}, J.KV{"options", J.Json.arr(MDock.opt.json(MDock.opts(q), 0n, picks))},
    J.KV{"own", J.Json.str(own)}, J.KV{"mode", J.Json.str(mode)}, J.KV{"answered", J.Json.bool(MDock.answered(picks, own, mode))}])

def MDock.qs.json(qs: List<&2, J.Json>, +u: U.Ui, +ask: String, +i: Nat) -> List<&2, J.Json>:
  match qs:
    case Nil{}:
      Nil{}
    case +q <> t:
      MDock.q.json(q, MDock.picks(u, ask, i, q), MDock.own(u, ask, i), MDock.mode(u, ask, i)) <> MDock.qs.json(t, u, ask, 1n+i)

# the question shown: the one gone to, within the questions there are
def MDock.at(+u: U.Ui, +ask: String, +n: Nat) -> Nat:
  +i = {Maybe.default(&2, Nat, Nat.read(U.Ui.scratch(u, MDock.at.key(ask))), 0n) : Nat}
  Bool.pick(Nat, Nat.is_lt(i, n), i, Nat.sub(n, 1n))

def MDock.json.k(m: Maybe<&2, M.Ask>, +u: U.Ui) -> J.Json:
  match m:
    case Some{M.Ask{+id, _, _, _, _, _, +qs, _, _}}:
      +list = MDock.qs(qs)
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"at", J.Json.nat(MDock.at(u, id, List.length(&2, J.Json, list)))},
        J.KV{"questions", J.Json.arr(MDock.qs.json(list, u, id, 0n))},
        J.KV{"ready", J.Json.bool(MDock.all.go(list, u, id, 0n))}, J.KV{"sent", J.Json.bool(Bool.not(String.is_empty(U.Ui.scratch(u, MDock.sent.key(id)))))},
        J.KV{"discuss", J.Json.str("Discuss this")}, J.KV{"discussNote", J.Json.str("The agent explains the trade-offs and waits for your reply before deciding.")}])
    case None{}:
      J.Null{}

# the selected thread's dock (null when no questions wait)
def MDock.json(+u: U.Ui) -> J.Json:
  MDock.json.k(MDock.find(U.Asks.open(U.Ui.state.of(u), U.Ui.sel(u))), u)
