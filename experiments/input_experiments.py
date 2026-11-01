import sys, tempfile, os
sys.path.insert(0, os.path.dirname(__file__))
from pty_driver import Nvim
INIT = os.path.join(os.path.dirname(__file__), "input", "init.lua")
results = []
def check(name, cond, detail=""):
    results.append((name, cond)); print(("PASS " if cond else "FAIL ") + name, detail)
def fresh(text="hello world\nsecond line\nthird"):
    f = tempfile.mktemp(suffix=".txt"); open(f, "w").write(text)
    return Nvim(INIT, [f])

n = fresh()
n.send("l"); check("1 l moves right", n.lua("vim.api.nvim_win_get_cursor(0)")==[1,1])
n.send("j"); check("2 j moves down", n.lua("vim.api.nvim_win_get_cursor(0)")==[2,1])
n.send("k"); n.send("h"); check("3 k,h", n.lua("vim.api.nvim_win_get_cursor(0)")==[1,0])
n.send("x"); check("4 x -> OUR delete (single char)", n.lines()[0]=="ello world", n.lines()[0])
n.send("dd"); check("5 dd -> our line delete", n.lines()==["second line","third"], str(n.lines()))
n.send("i"); check("6 native mode stays n after i", n.native_mode()=="n", n.native_mode())
n.send("abc"); check("7 insert via buffer api", n.lines()[0]=="abcsecond line", n.lines()[0])
n.send("\x1b"); n.send("l"); check("8 esc leaves logical insert", n.lua("_G.EXP.mode")=="n")
n.close()

n = fresh("")
n.send("iHéllo→日本😀"); check("9 unicode insert", n.lines()[0]=="Héllo→日本😀", n.lines()[0])
n.send("\r\x7f"); check("10 enter and bs", n.lines()==["Héllo→日本😀",""], str(n.lines()))
n.close()

n = fresh("")
n.send("i"); n.send("".join(chr(97+i%26) for i in range(500)), delay=0)
exp = "".join(chr(97+i%26) for i in range(500))
check("11 fast burst ordering (500 chars, no delay)", n.lines()[0]==exp, n.lines()[0][:40])
n.close()

n = fresh("")
n.send("i"); n.send("\x1b[200~pasted text\x1b[201~")
check("12 bracketed paste in logical insert", "pasted text" in n.lines()[0], str(n.lines()))
n.send("\x1b")
n.send("\x1b[200~dd\nxx\x1b[201~")
check("12b paste in logical normal mode does not leak natively", n.lines()==["pasted text"], str(n.lines()))
n.close()

n = fresh()
n.send("\x1b[A\x1b[B\x1b[C\x1b[D\x1bOP\x1b[15~")  # arrows, F1, F5
check("13 special keys do not crash/leak", n.lines()==["hello world","second line","third"] and n.lua("_G.EXP.errors")==0, str(n.lua("_G.EXP.log")))
n.send(":"); n.send("q!\r")
check("14 ':' intercepted (nvim still alive, no native cmdline)", n.native_mode()=="n")
n.send("Z"); n.send("Z")
check("15 ZZ native not quitting", n.native_mode()=="n")
n.send("\x1b:")  # esc then colon
n.send("\x16"); n.send("\x17"); n.send("\x12")  # C-v C-w C-r
check("16 ctrl keys no native effect", n.lua("vim.fn.winnr(\"$\")")==1 and n.native_mode()=="n")
n.close()

n = fresh()
n.send("\x1c\x1c")  # C-\ C-\  => passthrough toggle (emergency escape)
check("17 emergency escape enables native passthrough", n.lua("_G.EXP.passthrough")==True)
n.send("x"); check("17b native x now works", n.lines()[0]=="ello world", n.lines()[0])
n.send("\x1c\x1c"); n.send("x")
check("17c re-engage hook", n.lua("_G.EXP.passthrough")==False)
n.close()

n = fresh()
n.send("E"); n.send("l")
check("18 callback error is contained, hook survives", n.lua("_G.EXP.errors")==1 and n.lua("vim.api.nvim_win_get_cursor(0)")==[1,1], str(n.lua("_G.EXP.last_err")))
n.send("x"); check("18b still ours after error", n.lines()[0]=="hllo world", n.lines()[0])
n.close()

bad = [r for r in results if not r[1]]
print(f"\n{len(results)-len(bad)}/{len(results)} passed"); sys.exit(1 if bad else 0)
