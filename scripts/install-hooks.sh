#!/usr/bin/env bash
# Point this clone at repo-managed hooks (run once after clone).
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath githooks
chmod +x githooks/* scripts/*.sh
echo "hooksPath → githooks ($(git rev-parse --show-toplevel)/githooks)"
