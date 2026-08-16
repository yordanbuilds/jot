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

# --- jot-open-inbox ----------------------------------------------------------

fresh_sandbox
run "$HERE/bin/jot-open-inbox"
check "open-inbox: launches editor on default file" \
  grep -q "^omarchy-launch-editor $SB/notes/inbox.md$" "$LOG"
check "open-inbox: creates the notes dir" [ -d "$SB/notes" ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"file":"~/elsewhere/in.md"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-open-inbox"
check "open-inbox: honors configured file" \
  grep -q "^omarchy-launch-editor $SB/elsewhere/in.md$" "$LOG"

# A directory it can't create is the one failure this row can hit, and the menu
# swallows stderr — so it has to say so out loud instead of opening a buffer
# that could never be saved.

fresh_sandbox
mkdir -p "$SB/.config/jot" "$SB/ro"
chmod 555 "$SB/ro"
printf '{"file":"~/ro/sub/in.md"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-open-inbox" && rc=0 || rc=$?
check "open-inbox: unopenable dir exits 1" [ "$rc" = "1" ]
check "open-inbox: unopenable dir notifies" \
  grep -q "^omarchy-notification-send Jot couldn't open the inbox" "$LOG"
check "open-inbox: unopenable dir never launches the editor" \
  not grep -q '^omarchy-launch-editor' "$LOG"
chmod 755 "$SB/ro"

# --- jot-setup ---------------------------------------------------------------

fresh_sandbox
run "$HERE/bin/jot-setup"
check "setup: writes default config" grep -q '"file": "~/notes/inbox.md"' "$SB/.config/jot/config.json"
check "setup: binds SUPER+N when free" grep -q 'o.bind("SUPER + N", "Jot"' "$SB/.config/hypr/bindings.lua"
check "setup: binding sits in marked block" grep -q -- '-- >>> jot >>>' "$SB/.config/hypr/bindings.lua"
MENUF="$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "setup: menu rows added" grep -q '"trigger.jot.down"' "$MENUF"
check "setup: menu open-inbox uses absolute path" grep -qF "$HERE/bin/jot-open-inbox" "$MENUF"
check "setup: menu block closes before brace" \
  bash -c 'tail -n 2 "$1" | head -n 1 | grep -q "<<< jot menu <<<"' _ "$MENUF"
check "setup: flag written" [ -e "$SB/.config/jot/.setup-done" ]
check "setup: ready notification" grep -q '^omarchy-notification-send Jot is ready' "$LOG"

before="$(cat "$SB/.config/hypr/bindings.lua")$(cat "$MENUF")"
run "$HERE/bin/jot-setup"
after="$(cat "$SB/.config/hypr/bindings.lua")$(cat "$MENUF")"
check "setup: second run is a no-op" [ "$before" = "$after" ]

fresh_sandbox
printf '{\n  "personal": {"icon":"x","label":"Personal"}\n}\n' >"$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
run "$HERE/bin/jot-setup"
check "setup: comma added to preceding menu entry" \
  grep -q '"personal": {"icon":"x","label":"Personal"},' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"

fresh_sandbox
echo '[{"modmask":64,"key":"N"}]' >"$SB/hyprctl.out"
run "$HERE/bin/jot-setup"
check "setup: taken key not bound" not grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"
check "setup: taken key noted in notification" grep -q 'taken' "$LOG"

fresh_sandbox
printf -- '-- >>> jot >>>\no.bind("SUPER + M", "Jot", "custom")\n-- <<< jot <<<\n' >"$SB/.config/hypr/bindings.lua"
run "$HERE/bin/jot-setup"
check "setup: existing jot block untouched" \
  [ "$(grep -c '>>> jot >>>' "$SB/.config/hypr/bindings.lua")" = "1" ]
check "setup: existing jot block keeps custom key" not grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"file":"~/custom.md"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-setup"
check "setup: existing config preserved" grep -q 'custom.md' "$SB/.config/jot/config.json"

# Setup never fails silently: a menu file it can't parse, or a missing hypr dir,
# still leaves a finished, flagged setup that says what it couldn't do.

fresh_sandbox
: >"$SB/.config/omarchy/extensions/omarchy-menu.jsonc"   # 0-byte, not absent
run "$HERE/bin/jot-setup" && rc=0 || rc=$?
check "setup: empty menu file exits 0" [ "$rc" = "0" ]
check "setup: empty menu file gets seeded and filled" \
  grep -q '>>> jot menu >>>' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "setup: empty menu file still writes flag" [ -e "$SB/.config/jot/.setup-done" ]

fresh_sandbox
MENUF="$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
printf '{ "a": 1 }\n' >"$MENUF"                          # no lone-} line to insert before
before="$(cat "$MENUF")"
run "$HERE/bin/jot-setup" && rc=0 || rc=$?
check "setup: unparseable menu exits 0" [ "$rc" = "0" ]
check "setup: unparseable menu left untouched" [ "$before" = "$(cat "$MENUF")" ]
check "setup: unparseable menu says so" grep -q "Couldn't add menu entries" "$LOG"
check "setup: unparseable menu still binds" grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"
check "setup: unparseable menu still writes flag" [ -e "$SB/.config/jot/.setup-done" ]
check "setup: unparseable menu still reports ready" \
  grep -q '^omarchy-notification-send Jot is ready' "$LOG"

fresh_sandbox
rm -rf "$SB/.config/hypr"
run "$HERE/bin/jot-setup" && rc=0 || rc=$?
check "setup: missing hypr dir exits 0" [ "$rc" = "0" ]
check "setup: missing hypr dir is created" [ -d "$SB/.config/hypr" ]
check "setup: missing hypr dir still binds" grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"
check "setup: missing hypr dir still writes flag" [ -e "$SB/.config/jot/.setup-done" ]

# --- jot-uninstall -----------------------------------------------------------

fresh_sandbox
printf -- '-- mine\no.bind("SUPER + B", "Mine", "x")\n' >"$SB/.config/hypr/bindings.lua"
printf '{\n  "personal": {"icon":"x","label":"Personal"}\n}\n' >"$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
run "$HERE/bin/jot-setup"
run "$HERE/bin/jot-append" "keep me"
run "$HERE/bin/jot-uninstall" </dev/null
check "uninstall: binding block gone" not grep -q 'jot' "$SB/.config/hypr/bindings.lua"
check "uninstall: user bindings survive" grep -q 'SUPER + B' "$SB/.config/hypr/bindings.lua"
check "uninstall: menu rows gone" not grep -q 'trigger.jot' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "uninstall: user menu entries survive" grep -q 'Personal' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "uninstall: config kept without --purge" [ -f "$SB/.config/jot/config.json" ]
check "uninstall: notes file untouched" grep -q 'keep me' "$SB/notes/inbox.md"

fresh_sandbox
run "$HERE/bin/jot-setup"
run "$HERE/bin/jot-uninstall" --purge
check "uninstall --purge: config dir removed" not test -d "$SB/.config/jot"

# .setup-done is setup's own bookkeeping, not your data: it goes even without
# --purge, so re-adding the plugin installs again instead of no-opping into a
# dead plugin. config.json is yours, and stays until you ask for --purge.

fresh_sandbox
run "$HERE/bin/jot-setup"
run "$HERE/bin/jot-uninstall" </dev/null
check "uninstall: setup flag cleared without --purge" not test -e "$SB/.config/jot/.setup-done"
check "uninstall: config kept when the flag goes" [ -f "$SB/.config/jot/config.json" ]
run "$HERE/bin/jot-setup"
check "reinstall: binding returns without --force" \
  grep -q 'o.bind("SUPER + N", "Jot"' "$SB/.config/hypr/bindings.lua"
check "reinstall: menu rows return without --force" \
  grep -q '"trigger.jot.down"' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"

# --- summary -----------------------------------------------------------------

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
