#!/usr/bin/env bash
# QML gate for Jot.qml. It enforces exactly two things — no more, and the
# comments below say so plainly, because an earlier version of this script
# claimed a guarantee it did not deliver.
#
#   Check 1 — it parses. qmllint must accept every .qml file in the plugin
#   root. A syntax error exits non-zero and fails the gate. This is what
#   catches JavaScript the QML engine's parser rejects but Node accepts:
#   object spread and friends. That enforcement is the real value here.
#
#   Check 2 — no new warning categories. qmllint cannot resolve the shell's
#   qs.* imports outside a running Quickshell, so it buries every overlay in
#   [import] / [unqualified] / [unresolved-type] noise — including the
#   first-party reference this overlay is modeled on. Rather than pretend
#   that noise away, the gate lints the reference too and compares the
#   deduplicated set of bracketed category tags. Categories the reference
#   also produces are environment noise and pass. A category only Jot.qml
#   produces is ours, and fails.
#
# What this gate does NOT catch, stated so nobody trusts it further than it
# goes: a typo in a qs.* member — Style.font.headng — is reported as
# [unqualified], a category the reference already triggers, so it sails
# through. Nothing here type-checks qs.* members. Only the live shell does.
#
# Machines without Quickshell or qmllint skip; so does a machine where the
# reference overlay is missing or cannot itself be parsed, since check 2 has
# no baseline to compare against there.
#
# Run: bash tests/qml-smoke.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLLINT=/usr/lib/qt6/bin/qmllint

if [[ ! -d /usr/lib/qt6/qml/Quickshell ]] || ! command -v "$QMLLINT" >/dev/null 2>&1; then
  echo "qml-smoke: skipped (Quickshell QML modules not installed)"
  exit 0
fi

OM="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
CONTROL="$OM/shell/plugins/reminders/ReminderFlow.qml"

# The bracketed tag qmllint prints at the end of each diagnostic, e.g.
#   Warning: Jot.qml:21:30: Unqualified access [unqualified]
# Deduplicated and sorted, ready for comm(1).
categories() { grep -oE '\[[a-z][a-z0-9-]*\]$' | sort -u; }

if [[ ! -f $CONTROL ]]; then
  echo "qml-smoke: skipped (reference overlay not found at $CONTROL)"
  exit 0
fi

control_out="$("$QMLLINT" -I "$OM/shell" "$CONTROL" 2>&1)"
if (( $? != 0 )); then
  echo "qml-smoke: skipped (qmllint cannot parse the reference overlay here)"
  exit 0
fi

jot_out="$("$QMLLINT" -I "$OM/shell" "$HERE"/*.qml 2>&1)"
if (( $? != 0 )); then
  printf '%s\n' "$jot_out" >&2
  echo "qml-smoke: FAIL (qmllint could not parse the plugin QML)" >&2
  exit 1
fi

new_categories="$(comm -13 \
  <(printf '%s\n' "$control_out" | categories) \
  <(printf '%s\n' "$jot_out" | categories))"

if [[ -n $new_categories ]]; then
  echo "qml-smoke: FAIL (warning categories absent from $(basename "$CONTROL"))" >&2
  while IFS= read -r category; do
    [[ -n $category ]] || continue
    echo "  $category" >&2
    printf '%s\n' "$jot_out" | grep -F -- "$category" | sed 's/^/    /' >&2
  done <<< "$new_categories"
  exit 1
fi

echo "qml-smoke: ok"
