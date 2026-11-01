"""Dev-only: drive a real nvim TUI through a pty, query state via --server --remote-expr."""
import os, pty, subprocess, time, select, json, tempfile, signal, struct, fcntl, termios

class Nvim:
    def __init__(self, init, files=(), cwd=None, env_extra=None, rows=30, cols=100):
        self.sock = tempfile.mktemp(prefix="nvsock", dir="/tmp")
        env = dict(os.environ, TERM="xterm-256color", NVIM_APPNAME="nin-test", **(env_extra or {}))
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            if cwd: os.chdir(cwd)
            os.execvpe("nvim", ["nvim", "--clean", "-u", init, "--listen", self.sock, *files], env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        for _ in range(100):
            if os.path.exists(self.sock): break
            time.sleep(0.05)
        self.drain(0.5)

    def drain(self, t=0.15):
        out = b""
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.02)
            if r:
                try: out += os.read(self.fd, 65536)
                except OSError: break
        return out

    def send(self, data, delay=0.0):
        if isinstance(data, str): data = data.encode()
        if delay:
            for b in [data[i:i+1] for i in range(len(data))]:
                os.write(self.fd, b); time.sleep(delay)
        else:
            os.write(self.fd, data)
        self.drain(0.2)

    def lua(self, expr):
        r = subprocess.run(["nvim", "--server", self.sock, "--remote-expr", f"luaeval('vim.json.encode({expr})')"],
                           capture_output=True, text=True, timeout=10)
        if r.returncode: raise RuntimeError(r.stderr)
        return json.loads(r.stdout)

    def lines(self): return self.lua("vim.api.nvim_buf_get_lines(0,0,-1,false)")
    def native_mode(self): return self.lua("vim.api.nvim_get_mode().mode")

    def close(self):
        try: os.kill(self.pid, signal.SIGKILL)
        except OSError: pass
        try: os.waitpid(self.pid, 0)
        except OSError: pass
        try: os.unlink(self.sock)
        except OSError: pass
