#!/bin/sh
#
# build.sh — Build a Docker image from any Dockerfile path.
#
# Usage: build.sh [-t <tag>] <dockerfile-path>
#
# Takes a path to a Dockerfile, derives the build context from its parent
# directory, and runs docker build.  The optional -t flag sets the image
# tag (default: my-app).

set -e

usage() {
  echo "Usage: $0 [-t <tag>] <dockerfile-path>"
  echo "  <dockerfile-path>   Path to a Dockerfile (e.g. ./base-image/Dockerfile.base)"
  echo "  -t <tag>            Image tag (default: my-app)"
  exit 1
}

tag="my-app"

while [ $# -gt 0 ]; do
  case "$1" in
    -t)
      tag="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      dockerfile="$1"
      shift
      ;;
  esac
done

if [ -z "$dockerfile" ]; then
  echo "Error: no dockerfile path specified"
  usage
fi

if [ ! -f "$dockerfile" ]; then
  echo "Error: file not found: $dockerfile"
  exit 1
fi

context="$(dirname "$dockerfile")"

echo "Building $dockerfile from context $context with tag $tag"
docker build -f "$dockerfile" -t "$tag" "$context"


### End of File
