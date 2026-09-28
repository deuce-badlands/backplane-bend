import Base
import ./check.bend as C
import ../src/web/dom.bend as D
import ../src/app/layout.bend as L

# The native window's markdown tables (layout.bend's TL.div): aligned
# monospaced rows under a rule, where a code block's div stays code.

def texts(ls: List<&2, L.TLine>) -> String:
  match ls:
    case Nil{}:
      ""
    case L.TLine{t, _, _, _, _} <> r:
      t ++ "\n" ++ texts(r)

def kids(n: D.Node) -> List<&2, D.Node>:
  match n:
    case D.El{_, _, _, ks}:
      ks
    case _:
      Nil{}

def first(+md: String) -> List<&2, D.Node>:
  kids(Maybe.default(&2, D.Node, List.head(&2, D.Node, D.Md.render(md)), D.Txt{""}))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("a table", texts(L.TL.div(first("| Net | Length |\n|---|---:|\n| IMU_SCK | 41.2 mm |\n| CS | 38 mm |"))),
      "Net     | Length \n--------+--------\nIMU_SCK | 41.2 mm\nCS      | 38 mm  \n\n")
    C.Check.str("a code block stays code", texts(L.TL.div(first("```\nx = 1\n```"))), "code\nx = 1\n\n")
