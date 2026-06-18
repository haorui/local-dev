#!/bin/bash
# Wrapper to make metastore startup idempotent:
# if the Derby metastore_db already exists, skip schema init on restart.
set -e

DATA_DIR="${HIVE_DATA_DIR:-/opt/hive/data}"
DB_DIR="${DATA_DIR}/metastore_db"

# Hadoop 3.x compat: restore org.apache.hadoop.metrics.Updater removed in Hadoop 3.x
# but still referenced by hive-exec MapRedTask.
METRICS_SHIM="${DATA_DIR}/hive-metrics1-shim.jar"
if [ -f "$METRICS_SHIM" ]; then
  cp "$METRICS_SHIM" /opt/hive/lib/
  echo "[entrypoint-wrapper] installed hive-metrics1-shim.jar"
fi

# Derby creates a "seg0" directory inside metastore_db once initialized.
if [ -d "${DB_DIR}/seg0" ]; then
  export IS_RESUME=true
  echo "[entrypoint-wrapper] metastore_db already initialized, skipping schema init"
else
  echo "[entrypoint-wrapper] metastore_db not initialized, will run initSchema"
fi

exec /entrypoint.sh "$@"
