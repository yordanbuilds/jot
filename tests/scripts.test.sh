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
  cat >"$SB/bin/omarchy-launch-editor" <<SHIM
#!/usr/bin/env bash
echo "omarchy-launch-editor \$*" >>"$LOG"
SHIM
  chmod +x "$SB/bin/omarchy-launch-editor"
  # Not a plain argv echo: the real omarchy-notification-send takes the body
  # positionally and only when it doesn't look like an option
  # (`if [[ $1 != -* ]]`), so a dash-leading body is silently swallowed into
  # option passthrough. The shim mirrors that rule — otherwise a caller that
  # loses its body every time would still look fine in this log.
  cat >"$SB/bin/omarchy-notification-send" <<SHIM
#!/usr/bin/env bash
headline="\$1"; shift
description=""
if ((\$# > 0)) && [[ \$1 != -* ]]; then description="\$1"; shift; fi
echo "omarchy-notification-send \$headline\${description:+ \$description}" >>"$LOG"
SHIM
  chmod +x "$SB/bin/omarchy-notification-send"
  cat >"$SB/bin/hyprctl" <<SHIM
#!/usr/bin/env bash
echo "hyprctl \$*" >>"$LOG"
cat "$SB/hyprctl.out" 2>/dev/null || echo "[]"
SHIM
  chmod +x "$SB/bin/hyprctl"
  # The floating-terminal launcher is shimmed, never run: a test that pops a
  # real window is a test nobody can run twice. $SB/bin comes first on PATH, so
  # this shadows the real launcher wherever the suite runs.
  cat >"$SB/bin/omarchy-launch-floating-terminal-with-presentation" <<SHIM
#!/usr/bin/env bash
echo "omarchy-launch-floating-terminal-with-presentation \$*" >>"$LOG"
SHIM
  chmod +x "$SB/bin/omarchy-launch-floating-terminal-with-presentation"
  # jot-uninstall ends in `exec omarchy plugin remove …`, which on a real box
  # takes the plugin away. This recording stub stands in for it, and the canary
  # it answers lets the uninstall tests prove they are talking to the stub
  # before they run at all.
  cat >"$SB/bin/omarchy" <<SHIM
#!/usr/bin/env bash
[[ \${1:-} == --canary ]] && { echo STUB; exit 0; }
echo "omarchy \$*" >>"$LOG"
SHIM
  chmod +x "$SB/bin/omarchy"
}

run() { HOME="$SB" PATH="$SB/bin:$PATH" "$@"; }

# The consent window is launched in the background, so its shim lands a moment
# after the script that launched it has exited.
waitlogged() { # <substring>
  local i
  for ((i = 0; i < 150; i++)); do
    grep -qF "$1" "$LOG" && return 0
    sleep 0.02
  done
  return 1
}

# --- jot (the dispatcher) ----------------------------------------------------
# The front door: bare `jot` is the overlay, every verb is the sibling script
# of that name. The dispatcher is copied into a sandbox plugin dir whose
# siblings are recording stubs — so routing is proven without a single real
# setup, bind, or uninstall running.

dispatcher_sandbox() {
  fresh_sandbox
  DISP="$SB/plugin/bin"
  mkdir -p "$DISP"
  cp "$HERE/bin/jot" "$DISP/jot"
  for s in jot-open-inbox jot-bind-key jot-setup jot-uninstall; do
    cat >"$DISP/$s" <<SHIM
#!/usr/bin/env bash
echo "$s \$*" >>"$LOG"
SHIM
    chmod +x "$DISP/$s"
  done
  cat >"$SB/bin/omarchy-shell" <<SHIM
#!/usr/bin/env bash
echo "omarchy-shell \$*" >>"$LOG"
SHIM
  chmod +x "$SB/bin/omarchy-shell"
}

dispatcher_sandbox
run "$DISP/jot"
check "jot: bare command toggles the overlay" \
  grep -q "^omarchy-shell shell toggle yordanbuilds.jot {}$" "$LOG"

dispatcher_sandbox
run "$DISP/jot" inbox
check "jot: inbox routes to jot-open-inbox" grep -q '^jot-open-inbox' "$LOG"

dispatcher_sandbox
run "$DISP/jot" bind-key
check "jot: bind-key routes to jot-bind-key" grep -q '^jot-bind-key' "$LOG"

dispatcher_sandbox
run "$DISP/jot" setup --force
check "jot: setup routes with its flags" grep -q '^jot-setup --force$' "$LOG"

dispatcher_sandbox
run "$DISP/jot" uninstall --purge
check "jot: uninstall routes with its flags" grep -q '^jot-uninstall --purge$' "$LOG"

# The link in ~/.local/bin is how anyone actually runs this, and $BASH_SOURCE
# there names the link, not the script. Resolving it is what keeps the siblings
# findable — this is the test that fails if the resolution is dropped.
dispatcher_sandbox
ln -s "$DISP/jot" "$SB/bin/jot"
run jot inbox
check "jot: routes the same through a symlink on PATH" grep -q '^jot-open-inbox' "$LOG"

dispatcher_sandbox
out="$(run "$DISP/jot" wat 2>&1)" && rc=0 || rc=$?
check "jot: unknown verb exits 1" [ "$rc" = "1" ]
check "jot: unknown verb says what it didn't understand" grep -q 'unknown command: wat' <<<"$out"
check "jot: unknown verb prints the usage" grep -q '^Usage:' <<<"$out"
check "jot: unknown verb runs nothing" [ ! -s "$LOG" ]

dispatcher_sandbox
out="$(run "$DISP/jot" --help)" && rc=0 || rc=$?
check "jot: --help exits 0" [ "$rc" = "0" ]
check "jot: --help lists the verbs" grep -q 'jot uninstall' <<<"$out"

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

# A newline at either edge of a capture is a stray Shift+Enter, not content.
# It used to become a permanent blank continuation line — two spaces on their
# own — or push the real thought off the templated first line.

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"template":"- {text}"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" $'a\n'
check "append: trailing newline writes exactly one line" \
  [ "$(cat "$SB/notes/inbox.md")" = '- a' ]
check "append: trailing newline leaves no blank continuation line" \
  not grep -qE '^[[:space:]]+$' "$SB/notes/inbox.md"

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"template":"- {text}"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" $'\nreal thought'
check "append: leading newline never templates an empty first line" \
  [ "$(cat "$SB/notes/inbox.md")" = '- real thought' ]

fresh_sandbox
mkdir -p "$SB/.config/jot"
printf '{"template":"- {text}"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" $'\n\nfirst\nsecond\n\n'
check "append: edge newlines stripped, interior kept" \
  [ "$(cat "$SB/notes/inbox.md")" = "$(printf -- '- first\n  second')" ]

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
  grep -qE "^omarchy-notification-send Jot couldn't save +precious thought" "$LOG"
chmod 755 "$SB/ro"

# The toast is the only trace a failed capture leaves, so it has to survive
# text the notifier could mistake for its own options.

fresh_sandbox
mkdir -p "$SB/.config/jot" "$SB/ro"
chmod 555 "$SB/ro"
printf '{"file":"~/ro/sub/inbox.md"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-append" '- buy milk' && rc=0 || rc=$?
check "append: dash-leading failure still notifies" \
  grep -q "^omarchy-notification-send Jot couldn't save" "$LOG"
check "append: dash-leading notification carries the text" \
  grep -q "buy milk" "$LOG"
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
# Setup writes no key of its own — it asks, in a window, and only the answer
# can bind. The question is a floating terminal running the prompt.
check "setup: takes no keybinding" not grep -q 'jot' "$SB/.config/hypr/bindings.lua"
check "setup: first load asks about the key" waitlogged 'jot-ask-key --prompt'
MENUF="$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "setup: menu rows added" grep -q '"trigger.jot.down"' "$MENUF"
check "setup: menu open-inbox uses absolute path" grep -qF "$HERE/bin/jot-open-inbox" "$MENUF"
check "setup: menu offers the shortcut" grep -q '"label": "Add SUPER+N shortcut"' "$MENUF"
check "setup: shortcut row uses absolute path" grep -qF "$HERE/bin/jot-bind-key" "$MENUF"
check "setup: menu block closes before brace" \
  bash -c 'tail -n 2 "$1" | head -n 1 | grep -q "<<< jot menu <<<"' _ "$MENUF"
check "setup: flag written" [ -e "$SB/.config/jot/.setup-done" ]
check "setup: ready notification" grep -q '^omarchy-notification-send Jot is ready' "$LOG"
check "setup: ready notification drops the menu pointer once it has asked" \
  not grep -q 'add the SUPER+N shortcut from the menu' "$LOG"

# That guard is the whole consent story in the menu: it has to answer "show
# me" while no shortcut exists and "hide me" the moment one does. Run the
# expression the menu would run, against the sandbox HOME.
guard="$(grep -o '"when": "[^"]*"' "$MENUF" | head -1 | cut -d'"' -f4)"
check "setup: shortcut row is guarded" [ -n "$guard" ]
check "shortcut row shows while the key is unbound" \
  bash -c "HOME='$SB'; $guard"
printf -- '-- >>> jot >>>\nbind\n-- <<< jot <<<\n' >>"$SB/.config/hypr/bindings.lua"
check "shortcut row hides once the binding exists" \
  bash -c "HOME='$SB'; ! { $guard; }"
sed -i '/>>> jot >>>/,/<<< jot <<</d' "$SB/.config/hypr/bindings.lua"

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
mkdir -p "$SB/.config/jot"
printf '{"file":"~/custom.md"}' >"$SB/.config/jot/config.json"
run "$HERE/bin/jot-setup"
check "setup: existing config preserved" grep -q 'custom.md' "$SB/.config/jot/config.json"

# The jot command is one symlink into ~/.local/bin — under the sandbox HOME
# here, never the real one. JOT_BIN_DIR is the seam for a PATH dir elsewhere.

fresh_sandbox
run "$HERE/bin/jot-setup"
check "setup: links the jot command" [ -L "$SB/.local/bin/jot" ]
check "setup: the link points at this checkout" \
  [ "$(readlink "$SB/.local/bin/jot")" = "$(readlink -f "$HERE/bin/jot")" ]
check "setup: the link is a working jot" \
  bash -c '"$1/.local/bin/jot" --help | grep -q "^Usage:"' _ "$SB"

fresh_sandbox
run env JOT_BIN_DIR="$SB/mybin" "$HERE/bin/jot-setup"
check "setup: JOT_BIN_DIR moves the link" [ -L "$SB/mybin/jot" ]
check "setup: the default dir stays empty then" not test -e "$SB/.local/bin/jot"

# A jot on your PATH that we didn't create is yours — setup says so and leaves
# it. A link to a checkout the plugin has outgrown is ours, and is repointed.

fresh_sandbox
mkdir -p "$SB/.local/bin"
echo 'mine' >"$SB/.local/bin/jot"
out="$(run "$HERE/bin/jot-setup" 2>&1)"
check "setup: a jot it didn't create is left alone" \
  [ "$(cat "$SB/.local/bin/jot")" = "mine" ]
check "setup: it says the jot was left alone" grep -q 'is not our symlink' <<<"$out"
check "setup: the rest of setup still ran" [ -f "$SB/.config/jot/config.json" ]

fresh_sandbox
mkdir -p "$SB/.local/bin"
ln -s "$SB/gone/bin/jot" "$SB/.local/bin/jot"
run "$HERE/bin/jot-setup"
check "setup: a link to an older checkout is repointed" \
  [ "$(readlink "$SB/.local/bin/jot")" = "$(readlink -f "$HERE/bin/jot")" ]

# Setup never fails silently: a menu file it can't parse still leaves a
# finished, flagged setup that says what it couldn't do.

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
check "setup: unparseable menu still writes config" [ -f "$SB/.config/jot/config.json" ]
check "setup: unparseable menu still writes flag" [ -e "$SB/.config/jot/.setup-done" ]
check "setup: unparseable menu still reports ready" \
  grep -q '^omarchy-notification-send Jot is ready' "$LOG"

# --- jot-ask-key -------------------------------------------------------------
# The first-load question: whether to ask at all, then the asking itself.

# A forced re-run does the setup work again; it is not a first load, so it never
# reopens a question that has already been answered.
fresh_sandbox
run "$HERE/bin/jot-setup"
check "ask: first load asked once" waitlogged 'jot-ask-key --prompt'
run "$HERE/bin/jot-setup" --force
check "ask: a forced re-run asks nothing" \
  [ "$(grep -c 'jot-ask-key --prompt' "$LOG")" = "1" ]

# A key someone else holds is not Jot's to offer: no window, and the
# notification goes back to saying where the shortcut waits.
fresh_sandbox
echo '[{"modmask":64,"key":"N"}]' >"$SB/hyprctl.out"
run "$HERE/bin/jot-setup"
check "ask: a taken key opens no window" not grep -q 'floating-terminal' "$LOG"
check "ask: a taken key keeps the menu pointer" \
  grep -q 'add the SUPER+N shortcut from the menu' "$LOG"

# A binding already in place answers the question before it is asked.
fresh_sandbox
printf -- '-- >>> jot >>>\nbind\n-- <<< jot <<<\n' >"$SB/.config/hypr/bindings.lua"
run "$HERE/bin/jot-setup"
check "ask: an existing binding opens no window" not grep -q 'floating-terminal' "$LOG"

# No launcher to ask through: fall back to the notification, never to silence.
fresh_sandbox
run env JOT_ASK_LAUNCHER=jot-no-such-launcher "$HERE/bin/jot-setup"
check "ask: a missing launcher opens no window" not grep -q 'floating-terminal' "$LOG"
check "ask: a missing launcher keeps the menu pointer" \
  grep -q 'add the SUPER+N shortcut from the menu' "$LOG"

# The question itself, as it runs inside the floating terminal. No tty here, so
# it takes the plain-read path and the answer comes from stdin.
fresh_sandbox
out="$(printf 'y\n' | run "$HERE/bin/jot-ask-key" --prompt 2>&1)"; rc=$?
check "prompt: asks in one line" grep -q 'Add the SUPER+N shortcut?' <<<"$out"
check "prompt: opens with the ready line" grep -q '^Jot is ready$' <<<"$out"
check "prompt: the summary names what setup added" \
  grep -q '^menu entries · ~/.config/jot/config.json · the jot command on your PATH$' <<<"$out"
check "prompt: piped output stays plain" [ "$out" = "${out//$'\e'/}" ]
check "prompt: yes binds the shortcut" grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"
check "prompt: yes exits cleanly" [ "$rc" = "0" ]

fresh_sandbox
out="$(printf 'n\n' | run "$HERE/bin/jot-ask-key" --prompt 2>&1)"; rc=$?
check "prompt: no writes no binding" not grep -q 'jot' "$SB/.config/hypr/bindings.lua"
check "prompt: no points at the menu row" grep -q 'from the Jot menu' <<<"$out"
check "prompt: no exits cleanly" [ "$rc" = "0" ]

fresh_sandbox
out="$(printf '\n' | run "$HERE/bin/jot-ask-key" --prompt 2>&1)"
check "prompt: silence declines" not grep -q 'jot' "$SB/.config/hypr/bindings.lua"
check "prompt: silence points at the menu row too" grep -q 'from the Jot menu' <<<"$out"

# The key can go while the window is opening; the prompt checks again before it
# asks, so it never offers what is no longer free.
fresh_sandbox
echo '[{"modmask":64,"key":"N"}]' >"$SB/hyprctl.out"
out="$(printf 'y\n' | run "$HERE/bin/jot-ask-key" --prompt 2>&1)"
check "prompt: a key taken meanwhile is not offered" [ -z "$out" ]
check "prompt: a key taken meanwhile is not bound" \
  not grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"

# --- jot-bind-key ------------------------------------------------------------
# The shortcut, and the only thing that ever writes one. It reports through
# notifications because the menu is where it runs from.

fresh_sandbox
BINDF="$SB/.config/hypr/bindings.lua"
run "$HERE/bin/jot-bind-key" >/dev/null && rc=0 || rc=$?
check "bind-key: exits 0 when the key is free" [ "$rc" = "0" ]
check "bind-key: binds SUPER+N" grep -q 'o.bind("SUPER + N", "Jot"' "$BINDF"
check "bind-key: binding sits in a marked block" grep -q -- '-- >>> jot >>>' "$BINDF"
check "bind-key: says the shortcut is live" \
  grep -q '^omarchy-notification-send Shortcut added SUPER+N opens Jot.' "$LOG"

before="$(cat "$BINDF")"
run "$HERE/bin/jot-bind-key" >/dev/null
check "bind-key: second run changes nothing" [ "$before" = "$(cat "$BINDF")" ]
check "bind-key: second run says it is already bound" \
  grep -q 'SUPER+N already opens Jot.' "$LOG"

# A key someone else holds is not Jot's to take, so it says so and stops —
# the block that would have claimed it is never written.
fresh_sandbox
echo '[{"modmask":64,"key":"N"}]' >"$SB/hyprctl.out"
run "$HERE/bin/jot-bind-key" >/dev/null && rc=0 || rc=$?
check "bind-key: taken key exits non-zero" [ "$rc" != "0" ]
check "bind-key: taken key is not bound" not grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"
check "bind-key: taken key names the fallback" \
  grep -q '^omarchy-notification-send SUPER+N is taken' "$LOG"

# A hand-edited block is the user's answer to this question already.
fresh_sandbox
printf -- '-- >>> jot >>>\no.bind("SUPER + M", "Jot", "custom")\n-- <<< jot <<<\n' >"$SB/.config/hypr/bindings.lua"
run "$HERE/bin/jot-bind-key" >/dev/null
check "bind-key: existing jot block untouched" \
  [ "$(grep -c '>>> jot >>>' "$SB/.config/hypr/bindings.lua")" = "1" ]
check "bind-key: existing jot block keeps its custom key" \
  not grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"

fresh_sandbox
rm -rf "$SB/.config/hypr"
run "$HERE/bin/jot-bind-key" >/dev/null && rc=0 || rc=$?
check "bind-key: missing hypr dir exits 0" [ "$rc" = "0" ]
check "bind-key: missing hypr dir is created" [ -d "$SB/.config/hypr" ]
check "bind-key: missing hypr dir still binds" grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"

# --- jot-uninstall -----------------------------------------------------------
# The last line of the script is the dangerous one: `exec omarchy plugin remove
# yordanbuilds.jot --yes` would uninstall the plugin off the machine running the
# suite. Every run below goes through this wrapper, and each one re-proves that
# `omarchy` resolves to the sandbox stub — a canary the real omarchy would
# reject as an unknown command. No proof, no run, and a loud failure.
#
# The answers are fed as a here-string and the output captured with a redirect,
# both on the call itself: a pipeline or a command substitution would run the
# wrapper in a subshell, where a canary failure could no longer count itself.
uninstall() { # <args...>
  if [[ "$(run omarchy --canary 2>/dev/null)" != STUB ]]; then
    FAIL=$((FAIL+1))
    echo "FAIL  uninstall: no omarchy stub on PATH — refusing to run jot-uninstall"
    return 1
  fi
  run "$HERE/bin/jot-uninstall" "$@"
}

fresh_sandbox
printf -- '-- mine\no.bind("SUPER + B", "Mine", "x")\n' >"$SB/.config/hypr/bindings.lua"
printf '{\n  "personal": {"icon":"x","label":"Personal"}\n}\n' >"$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
run "$HERE/bin/jot-setup"
run "$HERE/bin/jot-bind-key" >/dev/null
run "$HERE/bin/jot-append" "keep me"
uninstall <<<$'y\nn' >"$SB/out" 2>&1
check "uninstall: says what it is about to remove" grep -q 'This removes Jot' "$SB/out"
check "uninstall: asks for the whole thing first" grep -qF 'Remove Jot? [y/N]' "$SB/out"
check "uninstall: asks about the config second" grep -qF 'your config)? [y/N]' "$SB/out"
check "uninstall: the jot command's link is gone" not test -e "$SB/.local/bin/jot"
check "uninstall: binding block gone" not grep -q 'jot' "$SB/.config/hypr/bindings.lua"
check "uninstall: user bindings survive" grep -q 'SUPER + B' "$SB/.config/hypr/bindings.lua"
check "uninstall: menu rows gone" not grep -q 'trigger.jot' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "uninstall: user menu entries survive" grep -q 'Personal' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "uninstall: config kept without --purge" [ -f "$SB/.config/jot/config.json" ]
check "uninstall: notes file untouched" grep -q 'keep me' "$SB/notes/inbox.md"
# One command, all the way to the end: the plugin itself is the last removal.
check "uninstall: hands the plugin to omarchy" \
  grep -q '^omarchy plugin remove yordanbuilds.jot --yes$' "$LOG"

fresh_sandbox
run "$HERE/bin/jot-setup"
uninstall --purge <<<y >"$SB/out" 2>&1
check "uninstall --purge: config dir removed" not test -d "$SB/.config/jot"
check "uninstall --purge: plugin still removed after the purge" \
  grep -q '^omarchy plugin remove yordanbuilds.jot --yes$' "$LOG"
# --purge is the config answer given up front — the question it skips is that
# one, never the confirmation that anything happens at all.
check "uninstall --purge: still asks for the whole thing" grep -qF 'Remove Jot? [y/N]' "$SB/out"
check "uninstall --purge: does not ask about the config" not grep -q 'your config' "$SB/out"

# Saying no is a full stop: it happens before the first removal, so the machine
# is exactly as it was — and an unanswered run (no stdin at all) says no too.

fresh_sandbox
run "$HERE/bin/jot-setup"
run "$HERE/bin/jot-bind-key" >/dev/null
uninstall <<<n >"$SB/out" 2>&1 && rc=0 || rc=$?
check "uninstall: declining exits 0" [ "$rc" = "0" ]
check "uninstall: declining says nothing was removed" grep -q 'Nothing was removed' "$SB/out"
check "uninstall: declining never asks about the config" not grep -q 'your config' "$SB/out"
check "uninstall: declining keeps the menu rows" \
  grep -q 'trigger.jot' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "uninstall: declining keeps the binding" grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"
check "uninstall: declining keeps the jot command" [ -L "$SB/.local/bin/jot" ]
check "uninstall: declining keeps the setup flag" [ -e "$SB/.config/jot/.setup-done" ]
check "uninstall: declining never hands the plugin to omarchy" \
  not grep -q '^omarchy plugin remove' "$LOG"

fresh_sandbox
run "$HERE/bin/jot-setup"
uninstall </dev/null >"$SB/out" 2>&1 && rc=0 || rc=$?
check "uninstall: an unanswered run exits 0" [ "$rc" = "0" ]
check "uninstall: an unanswered run removes nothing" \
  grep -q 'trigger.jot' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "uninstall: an unanswered run keeps the config" [ -f "$SB/.config/jot/config.json" ]

# Yes to both is the purge, asked for one question later.
fresh_sandbox
run "$HERE/bin/jot-setup"
uninstall <<<$'y\ny' >"$SB/out" 2>&1
check "uninstall: yes to the config question purges" not test -d "$SB/.config/jot"
check "uninstall: yes to both still removes the plugin" \
  grep -q '^omarchy plugin remove yordanbuilds.jot --yes$' "$LOG"

# A jot on the PATH that setup refused to create is not this script's to
# delete either — only our own symlink goes.
fresh_sandbox
run "$HERE/bin/jot-setup"
rm -f "$SB/.local/bin/jot"
echo 'mine' >"$SB/.local/bin/jot"
uninstall <<<$'y\nn' >"$SB/out" 2>&1
check "uninstall: a jot we didn't link survives" [ "$(cat "$SB/.local/bin/jot")" = "mine" ]

# No omarchy to hand the plugin to: say which command finishes the job instead
# of dying on a bare "command not found". PATH is cut down to symlinks for the
# two coreutils the script needs, so omarchy is genuinely absent rather than
# shadowed — and that absence is asserted before the run.
fresh_sandbox
run "$HERE/bin/jot-setup"
mkdir -p "$SB/minbin"
ln -s "$(command -v sed)" "$SB/minbin/sed"
ln -s "$(command -v rm)" "$SB/minbin/rm"
check "uninstall: the cut-down PATH has no omarchy at all" \
  bash -c 'PATH="$1"; ! command -v omarchy >/dev/null' _ "$SB/minbin"
out="$(HOME="$SB" PATH="$SB/minbin" "$BASH" "$HERE/bin/jot-uninstall" --purge <<<y 2>&1)"; rc=$?
check "uninstall: a missing omarchy exits 0" [ "$rc" = "0" ]
check "uninstall: a missing omarchy names the command to finish with" \
  grep -q 'finish with: omarchy plugin remove yordanbuilds.jot' <<<"$out"
check "uninstall: a missing omarchy still did the removals" not test -d "$SB/.config/jot"

# .setup-done is setup's own bookkeeping, not your data: it goes even without
# --purge, so re-adding the plugin installs again instead of no-opping into a
# dead plugin. config.json is yours, and stays until you ask for --purge.

fresh_sandbox
run "$HERE/bin/jot-setup"
uninstall <<<$'y\nn' >"$SB/out" 2>&1
check "uninstall: setup flag cleared without --purge" not test -e "$SB/.config/jot/.setup-done"
check "uninstall: config kept when the flag goes" [ -f "$SB/.config/jot/config.json" ]
run "$HERE/bin/jot-setup"
check "reinstall: menu rows return without --force" \
  grep -q '"trigger.jot.down"' "$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
check "reinstall: the shortcut is still asked for, not restored" \
  not grep -q 'SUPER + N' "$SB/.config/hypr/bindings.lua"

# --- summary -----------------------------------------------------------------

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
