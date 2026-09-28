import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/client.bend as U

# The simpler sidebar: quiet projects sink and fold away, the active view
# puts what waits on the person first and fades the recently settled, and
# a row's menu acts on it (Delete and Remove ask first).

def now() -> Nat:
  1000000n

def log() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "board", "/tmp/board", 100n},
   M.ProjectCreated{"p2", "enclosure", "/tmp/enclosure", 200n},
   M.ProjectCreated{"p3", "firmware", "/tmp/firmware", 300n},
   M.ProjectCreated{"p4", "case", "/tmp/case", 998000n},
   M.ThreadCreated{"a", "p1", "Power sequencing", M.Local{}, "", "", "claude", "", 900000n},
   M.ThreadCreated{"b", "p1", "Pin swap", M.Local{}, "", "", "claude", "", 900100n},
   M.ThreadCreated{"c", "p1", "Pick a regulator", M.Local{}, "", "", "claude", "", 900200n},
   M.ThreadCreated{"d", "p1", "Silk cleanup", M.Local{}, "", "", "claude", "", 900300n},
   M.ThreadCreated{"e", "p1", "Old spike", M.Local{}, "", "", "claude", "", 400n},
   M.ThreadCreated{"f", "p2", "Wall bracket", M.Local{}, "", "", "claude", "", 999000n},
   M.TurnChanged{"a", M.Running{}, 999100n},
   M.TurnChanged{"b", M.Completed{}, 999200n},
   M.AskOpened{"q1", "c", "input", "AskUserQuestion", "Which one?", "", "", 999300n},
   M.ThreadSettled{"d", True{}, 999000n},
   M.ThreadSettled{"e", True{}, 500n},
   M.ThreadSettled{"f", True{}, 999500n}]

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def sent.go(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case U.Send{t} <> _:
      t
    case _ <> r:
      sent.go(r)

def sent(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      sent.go(cs)

def base() -> U.Ui:
  U.Ui.fold(log(), U.Ui.init(now()))

def st() -> M.State:
  M.State.replay(log(), M.State.empty())

def act(+u: U.Ui, +a: String, +v: String) -> U.Ui:
  ui(U.Ui.act(u, a, v))

def pids(+u: U.Ui) -> String:
  String.join(U.Side.projects(u), ",")

def labels(xs: List<&2, U.MItem>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case U.MItem{l, _, _, _} <> t:
      l <> labels(t)

def menu(+u: U.Ui) -> String:
  String.join(labels(U.Menu.items(u, False{})), ",")

def active(+q: String) -> String:
  String.join(U.Active.ids(U.Active.rows(st(), now(), q)), ",")

def faded(rs: List<&2, U.ARow>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Bool.show(U.ARow.faded(r)) <> faded(t)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("live, quiet, older folded", pids(base()), "p1,p2,p4")
    C.Check.str("older unfolds", pids(act(base(), "toggle-settled", "old-projects")), "p1,p2,p4,p3")
    C.Check.str("search reaches older", pids(act(base(), "bfield", "pq\u{1f}firm")), "p3")
    C.Check.str("view default", U.Side.view(st()), "projects")
    C.Check.str("view setting", U.Side.view(M.State.replay([M.SettingSet{"sidebar.view", "active", 1n}], st())), "active")
    C.Check.str("waits on you first, recent settled last", active(""), "c,b,a,f,d")
    C.Check.str("settled faded", String.join(faded(U.Active.rows(st(), now(), "")), ","), "False,False,False,True,True")
    C.Check.str("active search by project", active("enclosure"), "f")
    C.Check.str("active search by title", active("regul"), "c")
    C.Check.str("menu opens", U.Ui.scratch(act(base(), "row-menu", "d"), "@menu"), "t:d")
    C.Check.str("same again shuts", U.Ui.scratch(act(act(base(), "row-menu", "d"), "row-menu", "d"), "@menu"), "")
    C.Check.str("settled menu", menu(act(base(), "row-menu", "d")), "Bring back,Archive,Delete")
    C.Check.str("open menu", menu(act(base(), "row-menu", "a")), "Pin,Settle,Snooze 1 hour,Snooze until tomorrow,Snooze 1 week,Archive,Delete")
    C.Check.str("delete asks, menu stays", menu(act(act(base(), "row-menu", "d"), "row-delete", "d")), "Bring back,Archive,Click again to delete")
    C.Check.str("delete twice deletes", sent(U.Ui.act(act(act(base(), "row-menu", "d"), "row-delete", "d"), "row-delete", "d")), "{\"id\":0,\"m\":\"thread.delete\",\"p\":{\"thread\":\"d\"}}")
    C.Check.str("deleted shuts", U.Ui.scratch(act(act(act(base(), "row-menu", "d"), "row-delete", "d"), "row-delete", "d"), "@menu"), "")
    C.Check.str("pin sends", sent(U.Ui.act(act(base(), "row-menu", "a"), "row-pin", "a")), "{\"id\":0,\"m\":\"thread.pin\",\"p\":{\"thread\":\"a\"}}")
    C.Check.str("pin shuts", U.Ui.scratch(act(act(base(), "row-menu", "a"), "row-pin", "a"), "@menu"), "")
    C.Check.str("bring back sends", sent(U.Ui.act(act(base(), "row-menu", "d"), "row-unsettle", "d")), "{\"id\":0,\"m\":\"thread.unsettle\",\"p\":{\"thread\":\"d\"}}")
    C.Check.str("other action shuts", U.Ui.scratch(act(act(base(), "row-menu", "a"), "toggle-settled", "p1"), "@menu"), "")
    C.Check.str("project menu", menu(act(base(), "proj-menu", "p1")), "New thread,Remove project")
    C.Check.str("rich project menu", String.join(labels(U.Menu.items(act(base(), "proj-menu", "p1"), True{})), ","), "New thread,Colour and icon,Remove project")
    C.Check.str("remove asks", menu(act(act(base(), "proj-menu", "p1"), "proj-remove", "p1")), "New thread,Click again to remove")
    C.Check.str("menu title", U.Menu.title(act(base(), "proj-menu", "p2")), "enclosure")
    C.Check.str("close disarms", U.Ui.scratch(act(act(act(base(), "row-menu", "d"), "row-delete", "d"), "menu-close", ""), "@del"), "")
    C.Check.str("enter opens first active", U.Ui.sel(act(act(U.Ui.fold(List.append(&2, M.Change, log(), [M.SettingSet{"sidebar.view", "active", 1n}]), U.Ui.init(now())), "bfield", "pq\u{1f}pin swap"), "proj-go", "")), "b")
