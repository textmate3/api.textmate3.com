# Sourced by other scripts in this directory. Loads chruby and activates the
# Ruby version specified in .ruby-version. Idempotent.

if ! command -v chruby >/dev/null 2>&1; then
  # chruby.sh references unset variables; temporarily relax `set -u`.
  __api_chruby_had_nounset=0
  case "$-" in *u*) __api_chruby_had_nounset=1; set +u ;; esac

  if [ -f /opt/homebrew/opt/chruby/share/chruby/chruby.sh ]; then
    # shellcheck disable=SC1091
    source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
  elif [ -f /usr/local/opt/chruby/share/chruby/chruby.sh ]; then
    # shellcheck disable=SC1091
    source /usr/local/opt/chruby/share/chruby/chruby.sh
  else
    echo "chruby not found; install via 'brew install chruby ruby-install'" >&2
    exit 1
  fi

  [ "$__api_chruby_had_nounset" = "1" ] && set -u
  unset __api_chruby_had_nounset
fi

ruby_version_file="$(dirname "$0")/../.ruby-version"
if [ -f "$ruby_version_file" ]; then
  chruby "$(cat "$ruby_version_file")"
fi
