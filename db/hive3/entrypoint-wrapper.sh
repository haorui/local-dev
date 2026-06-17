#!/bin/bash
# Wrapper to make metastore startup idempotent:
# if the Derby metastore_db already exists, skip schema init on restart.
set -e

DATA_DIR="${HIVE_DATA_DIR:-/opt/hive/data}"
DB_DIR="${DATA_DIR}/metastore_db"

# Derby creates a "seg0" directory inside metastore_db once initialized.
# If that exists, the schema is already in place — no need to re-run initSchema.
if [ -d "${DB_DIR}/seg0" ]; then
  export IS_RESUME=true
  echo "[entrypoint-wrapper] metastore_db already initialized, skipping schema init"
else
  echo "[entrypoint-wrapper] metastore_db not initialized, will run initSchema"
fi

exec /entrypoint.sh "$@"
