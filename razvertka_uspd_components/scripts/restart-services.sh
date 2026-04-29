#!/usr/bin/env bash
# Прокси к install.sh --restart-services (логика в scripts/lib/razvertka-restart.sh).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$R/install.sh" --restart-services "$@"
