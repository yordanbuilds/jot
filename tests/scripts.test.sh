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

# The two-line contract itself: line 1 absolute, exactly two lines, exit 0 —
# whatever a hand-edited config.json throws at it.

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '%s' '{"file":"notes/inbox.md"}' >"$SB/.config/jot/config.json"
out="$(run "$HERE/bin/jot-config")"; rc=$?
check "config: exits 0" [ "$rc" -eq 0 ]
check "config: prints exactly two lines" [ "$(wc -l <<<"$out")" -eq 2 ]
check "config: relative file anchored at HOME" [ "$(sed -n 1p <<<"$out")" = "$SB/notes/inbox.md" ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '%s' '{"file":["a","b"]}' >"$SB/.config/jot/config.json"
out="$(run "$HERE/bin/jot-config" 2>"$SB/stderr")"
check "config: non-string file falls back" [ "$(sed -n 1p <<<"$out")" = "$SB/notes/inbox.md" ]
check "config: non-string file stays two lines" [ "$(wc -l <<<"$out")" -eq 2 ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '%s' '{"template":"- {text}\nrogue"}' >"$SB/.config/jot/config.json"
out="$(run "$HERE/bin/jot-config")"
check "config: multi-line template keeps first line" [ "$(sed -n 2p <<<"$out")" = "- {text}" ]
check "config: multi-line template stays two lines" [ "$(wc -l <<<"$out")" -eq 2 ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '%s' '"a bare string"' >"$SB/.config/jot/config.json"
out="$(run "$HERE/bin/jot-config" 2>"$SB/stderr")"
check "config: non-object config falls back" [ "$(sed -n 1p <<<"$out")" = "$SB/notes/inbox.md" ]
check "config: non-object config stays two lines" [ "$(wc -l <<<"$out")" -eq 2 ]
check "config: non-object config is silent on stderr" [ ! -s "$SB/stderr" ]

# --- jot-append --------------------------------------------------------------

fresh_sandbox
run "$HERE/bin/jot-append" "call the bank"
check "append: creates dir and file" [ -f "$SB/notes/inbox.md" ]
check "append: default template renders" \
  grep -qE '^- \[ \] 20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} call the bank$' "$SB/notes/inbox.md"

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"template":"- {text}"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" '50% off & a/b \ test'
check "append: metacharacters stay literal" \
  [ "$(cat "$SB/notes/inbox.md")" = '- 50% off & a/b \ test' ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"template":"- {text}"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" $'first\nsecond\nthird'
expected=$'- first\n  second\n  third'
check "append: multiline continuation indent" [ "$(cat "$SB/notes/inbox.md")" = "$expected" ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"template":"* note:"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" "hello"
check "append: template without {text} still captures" \
  [ "$(cat "$SB/notes/inbox.md")" = '* note: hello' ]

fresh_sandbox
run "$HERE/bin/jot-append" ""
check "append: empty text writes nothing" not test -e "$SB/notes/inbox.md"
run "$HERE/bin/jot-append" $'  \n '
check "append: whitespace-only writes nothing" not test -e "$SB/notes/inbox.md"

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"template":"- {text}"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" "one"
run "$HERE/bin/jot-append" "two"
check "append: appends, never overwrites" [ "$(wc -l <"$SB/notes/inbox.md")" = "2" ]

fresh_sandbox
mkdir -p "$SB/.config/jot" "$SB/ro"
chmod 555 "$SB/ro"
printf '{"file":"~/ro/sub/inbox.md"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" "precious thought" && rc=0 || rc=$?
check "append: failure exits non-zero" [ "$rc" != "0" ]
check "append: failure notification carries the text" \
  grep -q "^omarchy-notification-send Jot couldn't save precious thought" "$LOG"
chmod 755 "$SB/ro"

# --- summary -----------------------------------------------------------------

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
