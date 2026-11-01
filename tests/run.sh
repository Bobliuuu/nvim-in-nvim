#!/usr/bin/env bash
# All tests: Lua specs (headless Neovim) + the pty end-to-end story.
set -u
cd "$(dirname "$0")/.."
status=0
echo "== lua specs (unit + integration, headless nvim) =="
nvim --headless -u NONE -l tests/run.lua || status=1
echo
echo "== end-to-end (real nvim TUI in a pty, raw terminal input) =="
python3 tests/e2e_pty.py || status=1
echo
echo "== end-to-end: the blog config in layers (pty) =="
python3 tests/e2e_blog.py || status=1

echo
echo "== phase-0 input-interception experiments =="
python3 experiments/input_experiments.py | tail -1 || status=1
exit $status
