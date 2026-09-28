import Base
import ./check.bend as C
import ../src/web/dom.bend as D

def attrs(as: List<&2, D.Attr>) -> String:
  match as:
    case Nil{}:
      ""
    case D.At{n, v} <> t:
      " " ++ n ++ "=" ++ v ++ attrs(t)
    case D.On{e, a} <> t:
      " on" ++ e ++ "=" ++ a ++ attrs(t)

def shows(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}:
      ""
    case D.Txt{s} <> t:
      s ++ shows(t)
    case D.El{+tag, _, as, ks} <> t:
      "<" ++ tag ++ attrs(as) ++ ">" ++ shows(ks) ++ "</" ++ tag ++ ">" ++ shows(t)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("para", shows(D.Md.render("hello **bold** and `code`")), "<p>hello <strong>bold</strong> and <code>code</code></p>")
    C.Check.str("fence", shows(D.Md.render("a\n```js\nx = 1\n```\nb")), "<p>a</p><div class=codeblock><button class=copy title=Copy data-value=x = 1 onclick=copy>Copy</button><pre><code>x = 1</code></pre></div><p>b</p>")
    C.Check.str("list", shows(D.Md.render("# T\n- one\n- two")), "<h3>T</h3><ul><li>one</li><li>two</li></ul>")
    C.Check.str("stray", shows(D.Md.render("2 * 3 `x")), "<p>2 * 3 `x</p>")
    C.Check.str("html stays text", shows(D.Md.render("<b>hi</b>")), "<p><b>hi</b></p>")
    C.Check.str("table", shows(D.Md.render("before\n| | Pads | Range |\n|---|:--:|---|\n| Chips | 2 (20) | **3** |\n| Level | ~27 dB | `x` |\nafter")), "<p>before</p><div class=mdtable><table><tr><th></th><th>Pads</th><th>Range</th></tr><tr><td>Chips</td><td>2 (20)</td><td><strong>3</strong></td></tr><tr><td>Level</td><td>~27 dB</td><td><code>x</code></td></tr></table></div><p>after</p>")
    C.Check.str("table without header", shows(D.Md.render("| a | b |\n| c | d |")), "<div class=mdtable><table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table></div>")
