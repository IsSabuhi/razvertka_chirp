#!/usr/bin/env bash
# Прокси к install.sh --upgrade (логика в scripts/lib/).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$R/install.sh" --upgrade "$@"
