#!/usr/bin/env bash
# QML gate for Jot.qml. It enforces exactly two things — no more, and the
# comments below say so plainly, because an earlier version of this script
# claimed a guarantee it did not deliver.
#
#   Check 1 — it parses. qmllint must accept every .qml file in the plugin
#   root. A syntax error exits non-zero and fails the gate. This is what
#   catches JavaScript the QML engine's parser rejects but Node accepts:
#   object spread and friends.
#
#   Check 2 — every name comes from somewhere. The overlay is written against
#   qs.Ui and qs.Commons, Omarchy's shell kit, and qmllint resolves a module by
#   looking for its directory under an import root — so `import qs.Ui` needs a
#   root holding `qs/Ui/qmldir`. Omarchy's `shell/` directory is that tree one
#   level down: it holds `Ui/` and `Commons/`, whose qmldir files declare
#   `module qs.Ui` and `module qs.Commons`. The gate builds a temporary root
#   containing a single `qs` symlink pointing at the shell, hands it to qmllint
#   with -I, and then fails on the diagnostics that only mean something once
#   the kit is resolved:
#
#     Could not find property "X".   — a property the type does not declare
#     X was not found. …imports…     — a type the kit does not export
#     … not found on type "T".       — a member the type does not have
#
#   qmllint reports all three as warnings and still exits 0, so the gate
#   promotes them itself. Before the import root existed, none of them could be
#   trusted: without the kit *every* qs.* type is unknown, so a clean overlay
#   produced dozens of them and a misspelled one produced dozens plus one.
#
# What this gate does NOT catch, stated so nobody trusts it further than it
# goes: `not found on type "QObject"` is excluded, because Style and Color hand
# out their tokens as inline QtObject instances and qmllint reads the declared
# type, not the instance — so every *correct* token (Style.font.family,
# Color.menu.background) reports as missing. That means a typo inside those bags
# — Style.font.headng — is indistinguishable from them and still sails through.
# Only the live shell catches that one. Unqualified access is left a warning for
# the same reason: the kit's own components trip it.
#
# Machines without Quickshell or qmllint skip. A machine with Quickshell but no
# Omarchy checkout runs check 1 only, and says so — the gate never fails for a
# missing Omarchy.
#
# Run: bash tests/qml-smoke.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLLINT=/usr/lib/qt6/bin/qmllint

if [[ ! -d /usr/lib/qt6/qml/Quickshell ]] || ! command -v "$QMLLINT" >/dev/null 2>&1; then
  echo "qml-smoke: skipped (Quickshell QML modules not installed)"
  exit 0
fi

# OMARCHY_QMLLINT_SHELL is the seam CI uses to point at a checkout; a dev
# machine needs nothing.
shell_dir=""
for candidate in "${OMARCHY_QMLLINT_SHELL:-}" "${OMARCHY_PATH:+$OMARCHY_PATH/shell}" /usr/share/omarchy/shell; do
  if [[ -n $candidate && -d $candidate/Ui && -d $candidate/Commons ]]; then
    shell_dir="$candidate"
    break
  fi
done

lint_args=()
if [[ -n $shell_dir ]]; then
  import_root="$(mktemp -d)"
  trap 'rm -rf "$import_root"' EXIT
  ln -s "$shell_dir" "$import_root/qs"
  lint_args=(-I "$import_root")
fi

lint_out="$("$QMLLINT" ${lint_args[@]+"${lint_args[@]}"} "$HERE"/*.qml 2>&1)"
lint_status=$?

if [[ $lint_status -ne 0 ]]; then
  printf '%s\n' "$lint_out" >&2
  echo "qml-smoke: FAIL (qmllint could not parse the plugin QML)" >&2
  exit 1
fi

if [[ -z $shell_dir ]]; then
  echo "qml-smoke: ok (no Omarchy shell found — kit names unchecked)"
  exit 0
fi

kit_misses="$(printf '%s\n' "$lint_out" \
  | grep -E 'Could not find property "|was not found\. Did you add all imports|not found on type "' \
  | grep -v 'not found on type "QObject"')"

if [[ -n $kit_misses ]]; then
  echo "qml-smoke: FAIL — names the shell kit does not have:" >&2
  printf '%s\n' "$kit_misses" | sed 's/^/  /' >&2
  exit 1
fi

echo "qml-smoke: ok (kit resolved from $shell_dir)"
