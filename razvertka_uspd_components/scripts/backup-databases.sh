#!/usr/bin/env bash
# Прокси к install.sh --backup (логика в scripts/lib/).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$R/install.sh" --backup "$@"
