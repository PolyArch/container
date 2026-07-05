#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$repo_dir/container.sh"
local_bin="${HOME:-$PWD}/.local/bin"
link="$local_bin/container"

mkdir -p "$local_bin"
ln -sfn "$target" "$link"
printf 'Installed: %s -> %s\n' "$link" "$target"
