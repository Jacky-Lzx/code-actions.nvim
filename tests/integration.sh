#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export CODE_ACTIONS_ROOT="$root"
export SNACKS_DIR="${SNACKS_DIR:-$HOME/.local/share/nvim/lazy/snacks.nvim}"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_tmp/state"
export XDG_CACHE_HOME="$test_tmp/cache"
export NVIM_LOG_FILE="$test_tmp/nvim.log"
nvim --headless -u NONE -i NONE -l "$root/tests/integration.lua"
CODE_ACTIONS_BACKEND=delta CODE_ACTIONS_DELTA_COMMAND="$test_tmp/missing-delta" \
  CODE_ACTIONS_EXPECT_DELTA=0 nvim --headless -u NONE -i NONE -l "$root/tests/integration.lua"
cat > "$test_tmp/slow-delta" <<'EOF'
#!/usr/bin/env python3
import sys, time
sys.stdin.read()
time.sleep(10)
EOF
chmod +x "$test_tmp/slow-delta"
CODE_ACTIONS_BACKEND=delta CODE_ACTIONS_DELTA_COMMAND="$test_tmp/slow-delta" \
  CODE_ACTIONS_DELTA_TIMEOUT=50 CODE_ACTIONS_EXPECT_DELTA=0 \
  nvim --headless -u NONE -i NONE -l "$root/tests/integration.lua"
if command -v delta >/dev/null 2>&1; then
  CODE_ACTIONS_BACKEND=delta nvim --headless -u NONE -i NONE -l "$root/tests/integration.lua"
  CODE_ACTIONS_BACKEND=delta CODE_ACTIONS_DELTA_FAIL=1 CODE_ACTIONS_EXPECT_DELTA=0 \
    nvim --headless -u NONE -i NONE -l "$root/tests/integration.lua"
fi
