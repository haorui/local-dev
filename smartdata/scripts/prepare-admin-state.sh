#!/usr/bin/env bash
set -euo pipefail

# Usage: prepare-admin-state.sh [env-file] [smartdata-dir]
# Defaults: ./smartdata/.env and the script's parent smartdata/ directory.
# Values are KEY=value entries (last entry wins), with one matching outer quote
# pair removed; never sourced as shell.
env_file=${1:-./smartdata/.env}
smartdata_dir=${2:-$(cd -- "$(dirname -- "$0")/.." && pwd)}
smartdata_dir=$(cd -- "$smartdata_dir" && pwd)

read_value() {
  local v
  v=$(sed -n "s/^$1=//p" "$2" | tail -n 1)
  if [[ ${#v} -ge 2 ]]; then
    case $v in
      '"'*'"') v=${v#\"}; v=${v%\"} ;;
      "'"*"'") v=${v#\'}; v=${v%\'} ;;
    esac
  fi
  printf '%s' "$v"
}

resolve_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$smartdata_dir" "${1#./}" ;;
  esac
}

key_env_file=$(read_value SMARTDATA_ENV_FILE "$env_file")
if [[ -z "$key_env_file" ]]; then
  echo "set SMARTDATA_ENV_FILE in $env_file" >&2
  exit 1
fi
key_env_file=$(resolve_path "$key_env_file")

data_dir=$(read_value SMARTDATA_DATA_DIR "$env_file")
backup_dir=$(read_value SMARTDATA_BACKUP_DIR "$env_file")
secrets_dir=$(read_value SMARTDATA_SECRETS_DIR "$env_file")
data_dir=$(resolve_path "${data_dir:-./.data/admin-data}")
backup_dir=$(resolve_path "${backup_dir:-./.data/admin-backup}")
secrets_dir=$(resolve_path "${secrets_dir:-./.data/admin-secrets}")
mkdir -p -- "$data_dir" "$backup_dir" "$secrets_dir"

DB_ENCRYPT_KEY=
if [[ -f "$key_env_file" && -r "$key_env_file" ]]; then
  DB_ENCRYPT_KEY=$(read_value DB_ENCRYPT_KEY "$key_env_file")
fi
if [[ -z "$DB_ENCRYPT_KEY" ]]; then
  echo "DB_ENCRYPT_KEY missing in $key_env_file; needed for /run/secrets/database.key" >&2
  exit 1
fi

key_file=$secrets_dir/database.key
if [[ -e "$key_file" || -L "$key_file" ]]; then
  if [[ ! -f "$key_file" ]] || ! cmp -s "$key_file" <(printf '%s' "$DB_ENCRYPT_KEY"); then
    echo "database.key differs from DB_ENCRYPT_KEY in $key_env_file; refusing to start with a mismatched backup key (delete the file to regenerate)" >&2
    echo "Delete and regenerate only after the production installer's rotate-encrypt-key flow has re-encrypted existing at-rest data; simply changing DB_ENCRYPT_KEY and deleting the file makes that data unreadable." >&2
    exit 1
  fi
else
  (umask 077; printf '%s' "$DB_ENCRYPT_KEY" > "$key_file")
  chmod 600 "$key_file"
fi

printf 'admin state dirs ready: %s %s %s\n' "$data_dir" "$backup_dir" "$secrets_dir"
