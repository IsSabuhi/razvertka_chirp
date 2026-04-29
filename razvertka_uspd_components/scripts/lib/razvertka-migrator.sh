# shellcheck shell=bash
# razvertka-migrator.sh — скачивание/поиск chirpstack-v3-to-v4
download_migrator_to_tools() {
  local tools_dir="${SCRIPT_DIR}/tools"
  local ver="$CHIRPSTACK_MIGRATOR_VER"
  local tag="v${ver}"
  local mach uarch tarball url tmpdir candidate target
  command -v curl >/dev/null 2>&1 || {
    echo "Для авто-загрузки мигратора нужен curl." >&2
    return 1
  }
  mach="$(uname -m)"
  case "$mach" in
    x86_64) uarch="amd64" ;;
    aarch64) uarch="arm64" ;;
    armv7l) uarch="armv7" ;;
    *)
      echo "Авто-загрузка мигратора: неизвестная архитектура $mach" >&2
      return 1
      ;;
  esac
  tarball="chirpstack-v3-to-v4_${ver}_linux_${uarch}.tar.gz"
  url="https://github.com/chirpstack/chirpstack-v3-to-v4/releases/download/${tag}/${tarball}"
  target="${tools_dir}/chirpstack-v3-to-v4"
  mkdir -p "$tools_dir"
  tmpdir="$(mktemp -d)"
  echo ">>> Скачиваем утилиту миграции (${tarball})..." >&2
  if ! curl -fsSL "$url" -o "${tmpdir}/${tarball}"; then
    rm -rf "$tmpdir"
    echo "Не удалось скачать: $url" >&2
    return 1
  fi
  tar -xzf "${tmpdir}/${tarball}" -C "$tmpdir"
  candidate="$(find "$tmpdir" -type f \( -name 'chirpstack-v3-to-v4' -o -name 'chirpstack-v3-to-v4_*' \) ! -name '*.tar.gz' 2>/dev/null | head -1)"
  if [[ -z "$candidate" ]]; then
    candidate="$(find "$tmpdir" -maxdepth 4 -type f -perm -111 ! -name '*.tar.gz' 2>/dev/null | head -1)"
  fi
  if [[ -z "$candidate" || ! -f "$candidate" ]]; then
    rm -rf "$tmpdir"
    echo "В архиве не найден исполняемый файл мигратора." >&2
    return 1
  fi
  cp -f "$candidate" "$target"
  chmod +x "$target"
  rm -rf "$tmpdir"
  echo ">>> Мигратор сохранён: $target" >&2
  return 0
}

resolve_migrator_binary() {
  # Приоритет: явный путь → файлы в ./tools → скачивание → команда из PATH.
  local tools_dir="${SCRIPT_DIR}/tools"
  local p_default="${tools_dir}/chirpstack-v3-to-v4"
  local f cand

  if [[ -n "${CHIRPSTACK_MIGRATOR_BIN:-}" ]]; then
    if [[ -x "${CHIRPSTACK_MIGRATOR_BIN}" ]]; then
      echo "${CHIRPSTACK_MIGRATOR_BIN}"
      return 0
    fi
    die "CHIRPSTACK_MIGRATOR_BIN задан, но не исполняемый файл: ${CHIRPSTACK_MIGRATOR_BIN}"
  fi

  mkdir -p "$tools_dir"

  if [[ -f "$p_default" ]] && [[ ! -x "$p_default" ]]; then
    chmod +x "$p_default" 2>/dev/null || true
  fi
  if [[ -x "$p_default" ]]; then
    echo "$p_default"
    return 0
  fi

  shopt -s nullglob
  for f in "${tools_dir}"/chirpstack-v3-to-v4*; do
    [[ -f "$f" ]] || continue
    [[ -x "$f" ]] || chmod +x "$f" 2>/dev/null || true
    if [[ -x "$f" ]]; then
      shopt -u nullglob
      echo "$f"
      return 0
    fi
  done
  shopt -u nullglob

  if [[ "$SKIP_MIGRATOR_DOWNLOAD" == "1" ]]; then
    return 1
  fi
  if download_migrator_to_tools && [[ -x "$p_default" ]]; then
    echo "$p_default"
    return 0
  fi

  cand="$(command -v chirpstack-v3-to-v4 2>/dev/null || true)"
  if [[ -n "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  return 1
}
