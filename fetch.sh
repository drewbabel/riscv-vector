#!/usr/bin/env bash
# Retry network fetches
set -euo pipefail

TRIES=5
DELAY=10

retry() {
  local n=1
  until "$@"; do
    if [ "$n" -ge "$TRIES" ]; then
      echo "fetch.sh: failed $TRIES times: $*" >&2
      return 1
    fi
    echo "fetch.sh: try $n failed, retrying in $((DELAY * n)) s: $*" >&2
    sleep $((DELAY * n))
    n=$((n + 1))
  done
}

clone() {
  if [ -n "$3" ]; then
    git -C "$2" fetch -q origin '+refs/heads/*:refs/remotes/origin/*' &&
      git -C "$2" checkout -q "$3"
  else
    git -C "$2" fetch -q --depth 1 origin HEAD &&
      git -C "$2" checkout -q FETCH_HEAD
  fi
}

case "${1:-}" in
  url)
    retry curl -fsSL --connect-timeout 30 "$2" -o "$3"
    ;;
  git)
    if [ -e "$3" ]; then
      echo "fetch.sh: $3 already exists" >&2
      exit 1
    fi
    git init -q "$3"
    git -C "$3" remote add origin "$2"
    retry clone "$2" "$3" "${4:-}"
    ;;
  run)
    shift
    retry "$@"
    ;;
  *)
    echo "usage: fetch.sh url <url> <file> | git <url> <dir> [rev] | run <command...>" >&2
    exit 2
    ;;
esac
