#!/usr/bin/env bash
# Sandboxed tests for Jot's bash scripts. No live shell or Hyprland needed:
# omarchy-notification-send, omarchy-launch-editor, and hyprctl are PATH
# shims that log their arguments. Run: bash tests/scripts.test.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0

check() { # <label> <command...>
  local label="$1"; shift
  if "$@"; then PASS=$((PASS+1)); echo "ok    $label"
  else FAIL=$((FAIL+1)); echo "FAIL  $label"; fi
}

not() { ! "$@"; }

fresh_sandbox() {
  SB="$(mktemp -d)"
  LOG="$SB/calls.log"; : >"$LOG"
  mkdir -p "$SB/bin" "$SB/.config/hypr" "$SB/.config/omarchy/extensions"
  touch "$SB/.config/hypr/bindings.lua"
  local shim
  for shim in omarchy-notification-send omarchy-launch-editor; do
    cat >"$SB/bin/$shim" <<SHIM
#!/usr/bin/env bash
echo "$shim \$*" >>"$LOG"
SHIM
    chmod +x "$SB/bin/$shim"
  done
  cat >"$SB/bin/hyprctl" <<SHIM
#!/usr/bin/env bash
echo "hyprctl \$*" >>"$LOG"
cat "$SB/hyprctl.out" 2>/dev/null || echo "[]"
SHIM
  chmod +x "$SB/bin/hyprctl"
}

run() { HOME="$SB" PATH="$SB/bin:$PATH" "$@"; }

# --- jot-config --------------------------------------------------------------

fresh_sandbox
{ IFS= read -r f; IFS= read -r t; } < <(run "$HERE/bin/jot-config")
check "config: default file" [ "${f:-}" = "$SB/notes/inbox.md" ]
check "config: default template" [ "${t:-}" = '- [ ] %Y-%m-%d %H:%M {text}' ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"file":"~/x/in.md","template":"- {text}"}' >"$SB/.config/jot/config.json"
{ IFS= read -r f; IFS= read -r t; } < <(run "$HERE/bin/jot-config")
check "config: tilde-expanded custom file" [ "${f:-}" = "$SB/x/in.md" ]
check "config: custom template" [ "${t:-}" = "- {text}" ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"file":"~/x/in.md"}' >"$SB/.config/jot/config.json"
{ IFS= read -r f; IFS= read -r t; } < <(run "$HERE/bin/jot-config")
check "config: missing key falls back" [ "${t:-}" = '- [ ] %Y-%m-%d %H:%M {text}' ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf 'not json' >"$SB/.config/jot/config.json"
{ IFS= read -r f; IFS= read -r t; } < <(run "$HERE/bin/jot-config")
check "config: broken JSON falls back" [ "${f:-}" = "$SB/notes/inbox.md" ]
check "config: broken JSON notifies" grep -q '^omarchy-notification-send' "$LOG"

# --- summary -----------------------------------------------------------------

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
