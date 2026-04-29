#!/usr/bin/env bash
# Прокси к install.sh --status (логика в scripts/lib/).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$R/install.sh" --status "$@"
