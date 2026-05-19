#!/usr/bin/env bash
set -euo pipefail

##
## Hive2 Option A（HS2 Kerberos + 内嵌 Metastore + file:///）基础回归脚本
##
## 用途：
##   - 每次修改 hive2 配置 / 升级镜像后，快速验证当前环境是否仍然满足
##     透明代理所需的最小能力：Kerberos 建链 + 基本 DDL 正常。
##
## 使用前请按需修改下面几项配置。
##

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

## === 配置区（请根据本机环境调整） ==========================================

# 本机 beeline 路径（Hive 2.x 客户端）
HIVE_BEELINE_BIN="${HIVE_BEELINE_BIN:-/Users/haoruili/Documents/workspaces/dev/tools/apache-hive-2.3.9-bin/bin/beeline}"

# Kerberos 配置文件（与 hive4 一致）
KRB5_CONF="${KRB5_CONF:-${ROOT_DIR%/db/hive2}/db/hive/local_host/kerberos-host-krb5.conf}"

# 用于连接 HS2 的客户端主体与 keytab（示例：cli@TEST.COM）
KINIT_PRINCIPAL="${KINIT_PRINCIPAL:-cli@TEST.COM}"
KINIT_KEYTAB="${KINIT_KEYTAB:-${ROOT_DIR%/db/hive2}/kerberos/data/keytabs/cli.keytab}"

# HS2 Kerberos 服务主体（和 hive2 容器中配置一致）
HS2_PRINCIPAL="${HS2_PRINCIPAL:-hive/hadoop.test.com@TEST.COM}"

# HS2 JDBC URL（单实例直连；后续如切换到 ZK 模式，可在此处替换）
HS2_JDBC_URL="${HS2_JDBC_URL:-jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=${HS2_PRINCIPAL}}"

# 测试用库/表（只验证 DDL 能否成功写入 Metastore）
TEST_DB="${TEST_DB:-proxy_test_db}"
TEST_TABLE="${TEST_TABLE:-t_ping}"

## === 工具函数 ============================================================

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

require_file() {
  if [[ ! -f "$1" ]]; then
    log "ERROR: 缺少文件: $1"
    exit 1
  fi
}

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "ERROR: 找不到可执行文件: $1"
    exit 1
  fi
}

## === 前置检查 ============================================================

require_bin "$HIVE_BEELINE_BIN"
require_bin kinit
require_file "$KRB5_CONF"
require_file "$KINIT_KEYTAB"

export KRB5_CONFIG="$KRB5_CONF"
export HADOOP_OPTS="-Djava.security.krb5.conf=${KRB5_CONF} -Djavax.security.auth.useSubjectCredsOnly=false"

## === 测试步骤 ============================================================

step_kinit() {
  log "Step 1: 使用 keytab 为客户端主体获取 TGT: ${KINIT_PRINCIPAL}"
  kinit -kt "$KINIT_KEYTAB" "$KINIT_PRINCIPAL"
  log "Step 1: kinit 成功"
}

step_connect() {
  log "Step 2: 使用 Kerberos 连接 HiveServer2（仅执行轻量级语句）"
  # 等待 HS2 Thrift 端口完全就绪（避免刚启动时 TCP RST）
  sleep 10
  "$HIVE_BEELINE_BIN" \
    -u "${HS2_JDBC_URL}" \
    -e "set hive.cli.print.current.db=true; set hive.exec.dynamic.partition=true;" \
    >/tmp/hive2_test_connect.log 2>&1 || {
      log "ERROR: beeline 连接或执行轻量级语句失败，详见 /tmp/hive2_test_connect.log"
      exit 1
    }
  log "Step 2: beeline 连接 + 轻量级语句执行成功"
}

step_ddl() {
  log "Step 3: 执行基础 DDL（不依赖 MR），验证 Metastore 工作正常"
  local sql="
    create database if not exists ${TEST_DB};
    use ${TEST_DB};
    create table if not exists ${TEST_TABLE} (id int);
  "
  "$HIVE_BEELINE_BIN" \
    -u "${HS2_JDBC_URL}" \
    -e "$sql" \
    >/tmp/hive2_test_ddl.log 2>&1 || {
      log "ERROR: DDL 执行失败（可能是 Metastore 或权限问题），详见 /tmp/hive2_test_ddl.log"
      exit 1
    }
  log "Step 3: DDL 执行成功（库/表已在 Metastore 中创建或存在）"
}

main() {
  log "=== Hive2 Option A 基础回归测试开始 ==="
  log "ROOT_DIR       = ${ROOT_DIR}"
  log "HIVE_BEELINE   = ${HIVE_BEELINE_BIN}"
  log "KRB5_CONF      = ${KRB5_CONF}"
  log "KINIT_PRINC    = ${KINIT_PRINCIPAL}"
  log "HS2_JDBC_URL   = ${HS2_JDBC_URL}"
  log "TEST_DB/TABLE  = ${TEST_DB}.${TEST_TABLE}"

  step_kinit
  step_connect
  step_ddl

  log "=== 测试完成：当前环境满足 Kerberos 建链 + 基本 DDL 要求 ==="
  log "注意：依赖 MapReduce 的 SHOW / INSERT / 大查询 仍会因为 MR renewer 问题失败，这是已知限制。"
}

main "$@"


