"""Dev/test-only: drive a REAL nvim TUI through a pseudo-terminal with raw bytes, like a human typing.
State is read back over --listen/--remote-expr; a pyte virtual terminal renders what a user would see."""
import fcntl, json, os, pty, re, select, signal, struct, subprocess, tempfile, termios, time
import pyte

KEYS = {
    "Esc": "\x1b", "CR": "\r", "BS": "\x7f", "Tab": "\t", "Space": " ", "lt": "<",
    "Up": "\x1b[A", "Down": "\x1b[B", "Right": "\x1b[C", "Left": "\x1b[D", "Del": "\x1b[3~", "Home": "\x1b[H", "End": "\x1b[F",
    "C-c": "\x03", "C-k": "\x0b", "C-j": "\x0a", "C-h": "\x08", "C-l": "\x0c", "S-Tab": "\x1b[Z", "C-r": "\x12", "C-\\": "\x1c", "F1": "\x1bOP",
}


def tokenize(s):
    """'ihello<Esc>:w<CR>' -> ['i','h',...,'<Esc>',...]"""
    out, i = [], 0
    while i < len(s):
        m = re.match(r"<([A-Za-z0-9\\-]+)>", s[i:])
        if m and m.group(1) in KEYS:
            out.append(m.group(0)); i += m.end()
        else:
            out.append(s[i]); i += 1
    return out


class Nvim:
    def __init__(self, init, args=(), cwd=None, env=None, rows=40, cols=120):
        self.sock = tempfile.mktemp(prefix="rvsock", dir="/tmp")
        e = dict(os.environ, TERM="xterm-256color", **(env or {}))
        e.pop("NVIM", None)
        self.rows, self.cols = rows, cols
        self.screen = pyte.Screen(cols, rows)
        self.stream = pyte.ByteStream(self.screen)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            if cwd: os.chdir(cwd)
            os.execvpe("nvim", ["nvim", "--clean", "-u", init, "--listen", self.sock, *args], e)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        for _ in range(200):
            if os.path.exists(self.sock): break
            time.sleep(0.05)
        self.drain(0.8)

    def drain(self, t=0.12):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.02)
            if r:
                try: data = os.read(self.fd, 65536)
                except OSError: return
                self.stream.feed(data)

    def settle(self, quiet=0.1, limit=3.0):
        """Wait until the rendered screen stops changing (the TUI->server->TUI round trip has finished)."""
        end, prev = time.time() + limit, None
        while time.time() < end:
            self.drain(quiet)
            cur = tuple(self.screen.display)
            if cur == prev: return
            prev = cur

    def raw(self, data):
        os.write(self.fd, data.encode() if isinstance(data, str) else data)
        self.settle()

    def keys(self, s, per_key=0.0):
        """Send a key string. Each <Esc> is sent alone so it is not read as an Alt-chord."""
        toks = tokenize(s)
        buf = ""
        for t in toks:
            b = KEYS[t[1:-1]] if len(t) > 1 and t[0] == "<" and t[1:-1] in KEYS else t
            if b == "\x1b":
                if buf: self.raw(buf); buf = ""
                self.raw(b)
                self.drain(0.08)
            elif per_key:
                self.raw(b); time.sleep(per_key)
            else:
                buf += b
        if buf: self.raw(buf)
        self.settle()

    def paste(self, text):
        self.raw("\x1b[200~" + text + "\x1b[201~")

    def lua(self, expr):
        r = subprocess.run(["nvim", "--server", self.sock, "--remote-expr", f"luaeval(\"vim.json.encode({expr})\")"],
                           capture_output=True, text=True, timeout=15)
        if r.returncode: raise RuntimeError(r.stderr)
        return json.loads(r.stdout)

    def state(self):
        return self.lua("require('recursive_vim').state()")

    def focused(self):
        s = self.state()
        return s["editors"][str(s["focused"])], s

    def descendants(self):
        """pids of every OS process below the pty child. A TUI nvim is 2 processes (UI client + embedded server)."""
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid="], capture_output=True, text=True).stdout.split("\n")
        kids = {}
        for line in out:
            parts = line.split()
            if len(parts) == 2: kids.setdefault(int(parts[1]), []).append(int(parts[0]))
        found, todo = [], [self.pid]
        while todo:
            for k in kids.get(todo.pop(), []):
                found.append(k); todo.append(k)
        return sorted(found)

    def text(self):
        return "\n".join(l.rstrip() for l in self.screen.display)

    def wait_exit(self, timeout=5):
        end = time.time() + timeout
        while time.time() < end:
            self.drain(0.1)
            try:
                pid, _ = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                return True
            if pid: return True
        return False

    def close(self):
        try: os.kill(self.pid, signal.SIGKILL)
        except OSError: pass
        try: os.waitpid(self.pid, 0)
        except OSError: pass
        try: os.unlink(self.sock)
        except OSError: pass
