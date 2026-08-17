# Contributing

Issues and pull requests are welcome.

## Development

Jot runs from its checkout. Clone it where Omarchy loads plugins from:

```bash
git clone https://github.com/yordanbuilds/jot.git ~/.config/omarchy/plugins/yordanbuilds.jot
omarchy plugin enable yordanbuilds.jot
```

The shell does not reload already-loaded plugin QML — run
`omarchy restart shell` after editing `Jot.qml`. Bash scripts in `bin/`
take effect immediately.

## Tests

```bash
bash tests/scripts.test.sh   # the whole bash surface, sandboxed — no live session needed
bash tests/qml-smoke.sh      # qmllint against the shell modules (skips where unavailable)
```

Both run in CI on every push and pull request; a PR needs them green.
Please add tests for behavior you change.
