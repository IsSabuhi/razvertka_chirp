#!/usr/bin/env bash
# Прокси к install.sh --remove (логика в scripts/lib/, в т.ч. --only-chirp v3|v4).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$R/install.sh" --remove "$@"
