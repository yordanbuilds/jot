#!/usr/bin/env bash
# Lints Jot.qml against the installed Quickshell + Omarchy shell modules.
# Jot has no engine-portable JS library (all logic is bash), so the QML
# check is a dev-machine lint; machines without Quickshell skip it.
# Run: bash tests/qml-smoke.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -d /usr/lib/qt6/qml/Quickshell ]] || ! command -v /usr/lib/qt6/bin/qmllint >/dev/null 2>&1; then
  echo "qml-smoke: skipped (Quickshell QML modules not installed)"
  exit 0
fi

OM="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"

# Control: if the known-good first-party overlay doesn't lint here, this
# environment can't resolve the shell's qs.* imports — skip, don't lie.
CONTROL="$OM/shell/plugins/reminders/ReminderFlow.qml"
if [[ ! -f $CONTROL ]] || ! /usr/lib/qt6/bin/qmllint -I "$OM/shell" "$CONTROL" >/dev/null 2>&1; then
  echo "qml-smoke: skipped (qmllint cannot lint the control file ReminderFlow.qml here)"
  exit 0
fi

if ! /usr/lib/qt6/bin/qmllint -I "$OM/shell" "$HERE"/*.qml; then
  echo "qml-smoke: qmllint FAIL" >&2
  exit 1
fi
echo "qml-smoke: ok"
