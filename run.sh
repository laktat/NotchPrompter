#!/bin/sh
# Build NotchPrompter and (re)launch it. Same as `make run`.
set -e
cd "$(dirname "$0")"
exec make run "$@"
