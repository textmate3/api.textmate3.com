# Sourced by other scripts in this directory. Checks that rv is available.
#
# rv is the Ruby manager this project standardizes on. The scripts that need
# Ruby run their command through `rv run`, which reads the version from
# .ruby-version and installs it when it is missing.

if ! command -v rv >/dev/null 2>&1; then
  echo "rv not found; install via 'brew install rv' or from https://rv.dev" >&2
  exit 1
fi
