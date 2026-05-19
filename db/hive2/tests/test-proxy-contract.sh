#!/usr/bin/env bash
set -euo pipefail

##
## 应用层透明代理：接口契约测试骨架
##
## 目标：
##   - 在不依赖真实 Hive 执行路径的前提下，验证“代理进程”对上游暴露的接口形态是否满足预期；
##   - 后续可以在这里补充：
##       * 基于本地假 HS2 / Mock Thrift 的单元测试；
##       * 与真实 HS2 环境的轻量级集成测试。
##

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${PROXY_PORT:-18080}"

if [[ "${ENABLE_PROXY_TESTS:-0}" != "1" ]]; then
  log "SKIP: 尚未启动应用层透明代理进程（未设置 ENABLE_PROXY_TESTS=1），跳过本测试脚本。"
  exit 0
fi

log "=== 应用层透明代理接口契约测试（预留脚本）==="
log "ROOT_DIR    = ${ROOT_DIR}"
log "PROXY_HOST  = ${PROXY_HOST}"
log "PROXY_PORT  = ${PROXY_PORT}"

log "TODO: 在这里定义并实现你的代理接口测试，例如："
log "  - 使用你自己的客户端库连接 ${PROXY_HOST}:${PROXY_PORT}；"
log "  - 发送简单的 'SHOW DATABASES' / 'SELECT 1' 请求，检查返回的错误码/结构；"
log "  - 验证代理是否按约定返回权限拒绝 / 脱敏后的结果结构。"


