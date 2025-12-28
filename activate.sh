# mise + Git Bash integration with caching and cygpath
# Assumes: Git Bash, mise installed, cygpath and stat available

# If mise is not installed, do nothing
if ! command -v mise >/dev/null 2>&1; then
  return
fi

# Cache file location
MISE_GB_CACHE="${HOME}/.config/mise/mise_gitbash.cache"
# Cached variables
MISE_GB_MODE=""
MISE_GB_LOCAL_DIR=""
MISE_GB_LOCAL_CONF=""
MISE_GB_LOCAL_MTIME=0
MISE_GB_LOCAL_PATH=""
MISE_GB_GLOBAL_CONF="${HOME}/.config/mise/config.toml"
MISE_GB_GLOBAL_MTIME=0
MISE_GB_GLOBAL_PATH=""
MISE_GB_SUPPORT=0

_mise_gb_ensure_cache_dir() {
  local dir
  dir="${MISE_GB_CACHE%/*}"
  [ -d "$dir" ] || mkdir -p "$dir"
}

_mise_gb_load_cache() {
  if [ -f "$MISE_GB_CACHE" ]; then
    . "$MISE_GB_CACHE"
  fi
}

_mise_gb_save_cache() {
  _mise_gb_ensure_cache_dir
  local tmp="${MISE_GB_CACHE}.tmp"
  {
    printf 'MISE_GB_MODE=%q\n' "$MISE_GB_MODE"
    printf 'MISE_GB_LOCAL_DIR=%q\n' "$MISE_GB_LOCAL_DIR"
    printf 'MISE_GB_LOCAL_CONF=%q\n' "$MISE_GB_LOCAL_CONF"
    printf 'MISE_GB_LOCAL_MTIME=%q\n' "$MISE_GB_LOCAL_MTIME"
    printf 'MISE_GB_LOCAL_PATH=%q\n' "$MISE_GB_LOCAL_PATH"
    printf 'MISE_GB_GLOBAL_CONF=%q\n' "$MISE_GB_GLOBAL_CONF"
    printf 'MISE_GB_GLOBAL_MTIME=%q\n' "$MISE_GB_GLOBAL_MTIME"
    printf 'MISE_GB_GLOBAL_PATH=%q\n' "$MISE_GB_GLOBAL_PATH"
    printf 'MISE_GB_SUPPORT=%q\n' "$MISE_GB_SUPPORT"
  } >"$tmp"
  mv -f "$tmp" "$MISE_GB_CACHE"
}

_mise_gb_get_mtime() {
  local path="$1"
  if [ -n "$path" ] && [ -f "$path" ]; then
    stat -c %Y "$path" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Find nearest directory with mise config files
_mise_gb_find_local_dir() {
  local dir="$PWD"

  while :; do
    if [ -f "$dir/.mise.toml" ] || [ -f "$dir/mise.toml" ] || [ -f "$dir/.tool-versions" ]; then
      printf '%s\n' "$dir"
      return 0
    fi

    # reached root
    if [ "$dir" = "/" ]; then
      break
    fi

    dir=${dir%/*}
    [ -z "$dir" ] && break
  done

  return 1
}

# Pick the appropriate config file in a directory
_mise_gb_pick_conf() {
  local dir="$1"

  if [ -f "$dir/.mise.toml" ]; then
    printf '%s\n' "$dir/.mise.toml"
  elif [ -f "$dir/mise.toml" ]; then
    printf '%s\n' "$dir/mise.toml"
  elif [ -f "$dir/.tool-versions" ]; then
    printf '%s\n' "$dir/.tool-versions"
  else
    printf '%s\n' ""
  fi
}

# Convert Windows PATH to Unix style using cygpath
_mise_gb_convert_path() {
  local raw="$1"
  [ -z "$raw" ] && return 1

  if [[ "$raw" != *";"* ]]; then
    MISE_GB_SUPPORT=1
    printf '%s\n' "$raw"
    return 0
  else
    MISE_GB_SUPPORT=0
    if command -v cygpath >/dev/null 2>&1; then
      cygpath -u -p "$raw"
    fi
  fi
}

# Build the PATH by invoking mise and converting it
_mise_gb_build_path() {
  local win_path
  win_path=$(
    eval "$(command mise env bash 2>/dev/null)" >/dev/null 2>&1 || exit 1
    printf '%s\n' "$PATH"
  ) || return 1

  _mise_gb_convert_path "$win_path"
}

# Main logic: detect correct config, use cache or regenerate
_mise_gb_init() {
  local force="$1"
  local mode local_dir conf_file mtime cached_mtime cached_path current_conf new_path

  if local_dir=$(_mise_gb_find_local_dir); then
    mode="local"
    conf_file=$(_mise_gb_pick_conf "$local_dir")
    # If directory exists but files were removed, fall back to global
    if [ -z "$conf_file" ]; then
      mode="global"
      local_dir=""
      conf_file="$MISE_GB_GLOBAL_CONF"
    fi
  else
    mode="global"
    local_dir=""
    conf_file="$MISE_GB_GLOBAL_CONF"
  fi

  if [ "$mode" = "local" ]; then
    mtime=$(_mise_gb_get_mtime "$conf_file")
    cached_mtime="${MISE_GB_LOCAL_MTIME:-0}"
    cached_path="${MISE_GB_LOCAL_PATH:-}"
    current_conf="$MISE_GB_LOCAL_CONF"
  else
    mtime=$(_mise_gb_get_mtime "$conf_file")
    cached_mtime="${MISE_GB_GLOBAL_MTIME:-0}"
    cached_path="${MISE_GB_GLOBAL_PATH:-}"
    current_conf="$MISE_GB_GLOBAL_CONF"
  fi

  # If nothing changed and we have a cached path, just reapply it
  if [ "$force" != "force" ] && \
     [ "$MISE_GB_MODE" = "$mode" ] && \
     [ "$current_conf" = "$conf_file" ] && \
     [ "$mtime" = "$cached_mtime" ] && \
     [ -n "$cached_path" ]; then
    export PATH="$cached_path"
    return 0
  fi

  # Need to regenerate PATH
  new_path=$(_mise_gb_build_path) || return 1
  export PATH="$new_path"

  if [ "$mode" = "local" ]; then
    MISE_GB_LOCAL_DIR="$local_dir"
    MISE_GB_LOCAL_CONF="$conf_file"
    MISE_GB_LOCAL_MTIME="$mtime"
    MISE_GB_LOCAL_PATH="$new_path"
  else
    MISE_GB_GLOBAL_CONF="$conf_file"
    MISE_GB_GLOBAL_MTIME="$mtime"
    MISE_GB_GLOBAL_PATH="$new_path"
  fi

  MISE_GB_MODE="$mode"

  _mise_gb_save_cache
}

# Hook run before each prompt
_mise_gb_auto_env() {
  _mise_gb_init ""
}

# Manual command to force full reinit and show PATH
mise-path() {
  _mise_gb_init "force"

  if [ "$MISE_GB_SUPPORT" = "1" ]; then
    printf 'Note: mise appears to output Unix style PATH in Git Bash now.\n' >&2
    printf 'You can try using eval "$(mise activate bash)" instead of this script.\n' >&2
  fi

  printf '%s\n' "$PATH"
}

# Initial load on shell startup
_mise_gb_ensure_cache_dir
_mise_gb_load_cache
_mise_gb_init "startup"

# Add to PROMPT_COMMAND if not already present
case ";$PROMPT_COMMAND;" in
  *"_mise_gb_auto_env;"*)
    ;;
  *)
    if [ -n "$PROMPT_COMMAND" ]; then
      PROMPT_COMMAND="_mise_gb_auto_env; $PROMPT_COMMAND"
    else
      PROMPT_COMMAND="_mise_gb_auto_env"
    fi
    ;;
esac
