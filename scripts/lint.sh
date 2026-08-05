#!/bin/sh
#
# lint.sh — Lint Dockerfiles with hadolint.
#
# Usage: lint.sh [<dockerfile-path> ...]
#
# With no arguments, lints every Dockerfile.<name> in the repo.  With one or
# more paths, lints only those files.  Uses a local hadolint binary if it is
# on PATH, otherwise runs hadolint via Docker.

set -e

usage() {
  echo "Usage: $0 [<dockerfile-path> ...]"
  echo "  Lints the given Dockerfiles with hadolint."
  echo "  With no arguments, lints every Dockerfile in the repo."
  exit 1
}

case "$1" in
  -h|--help)
    usage
    ;;
esac

if command -v hadolint >/dev/null 2>&1; then
  hadolint_cmd="hadolint"
elif command -v docker >/dev/null 2>&1; then
  hadolint_cmd="docker run --rm -i hadolint/hadolint"
else
  echo "Error: hadolint is not installed and Docker is not available" >&2
  exit 1
fi

if [ $# -gt 0 ]; then
  dockerfiles="$*"
else
  dockerfiles="$(find . -type f -name 'Dockerfile.*' -not -path './.git/*' | sort)"
fi

[ -n "$dockerfiles" ] || {
  echo "No Dockerfiles found"
  exit 0
}

failed=0
for dockerfile in $dockerfiles; do
  echo "==> $dockerfile"
  $hadolint_cmd < "$dockerfile" || failed=1
done

exit $failed
