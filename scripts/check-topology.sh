#!/usr/bin/env bash
# check-topology.sh — drift check for the dev.smartdata.local topology SSOT.
#
# The canonical topology table lives in README.md ("服务拓扑" section). It restates
# routes and ports that are authoritatively defined elsewhere, so it can drift. This
# script re-confirms the table against its sources. Run it manually (low-frequency)
# after editing the table, nginx/conf.d/default.conf, or the sibling repos' dev config.
#
# Read-only. No network. Exits non-zero only when an intra-repo assertion (Layer 1) fails.
# Coverage is tiered and printed — it never silently claims a layer it did not run.
set -u

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)" || exit 2  # → local-dev repo root

README="README.md"
CONF="nginx/conf.d/default.conf"
SMARTDATA_DIR="../smartdata"

fail=0

# Extract the 服务拓扑 section (from its heading to the next top-level "## ").
section="$(awk '/^## 服务拓扑/{f=1;next} /^## /{f=0} f' "$README")"
if [ -z "$section" ]; then
  echo "FAIL: README 找不到「服务拓扑」段 — SSOT 表缺失或被改名"
  exit 1
fi

# Route prefixes referenced by the table: first path segment of each `/token`, minus
# non-route mentions like /etc/hosts.
routes="$(printf '%s\n' "$section" | grep -oE '`/[a-zA-Z0-9_-]+' | tr -d '`' | grep -vE '^/etc' | sort -u)"
# Ports referenced by the table: any 4-digit number inside the section.
ports="$(printf '%s\n' "$section" | grep -oE '[0-9]{4}' | sort -u)"

echo "== Layer 1: SSOT 表 vs ${CONF} (intra-repo, 恒运行) =="
for r in $routes; do
  if grep -qE "location [=~* ]*${r}" "$CONF"; then
    echo "  PASS  route ${r}*  → conf 有对应 location"
  else
    echo "  FAIL  route ${r}*  → conf 无对应 location"; fail=1
  fi
done
for p in $ports; do
  if grep -qE ":${p}([^0-9]|$)" "$CONF"; then
    echo "  PASS  port ${p}    → conf 命中"
  else
    echo "  FAIL  port ${p}    → conf 未命中（表里端口与反代不一致）"; fail=1
  fi
done

echo "== Layer 2: ports vs ${SMARTDATA_DIR} Procfile.dev + Makefile (best-effort) =="
if [ -d "$SMARTDATA_DIR" ]; then
  for p in $ports; do
    if grep -rqE "${p}([^0-9]|$)" "$SMARTDATA_DIR/Procfile.dev" "$SMARTDATA_DIR/Makefile" 2>/dev/null; then
      echo "  OK    port ${p}    → smartdata 源命中"
    else
      echo "  INFO  port ${p}    → 不在 smartdata Procfile/Makefile（由 nginx/vite 端拥有，非 smartdata 责任）"
    fi
  done
else
  echo "  SKIP  ${SMARTDATA_DIR} 不在旁 → 端口跨仓核对未运行（显式 SKIP，非静默通过）"
fi

echo "== Layer 3: image / registry =="
echo "  N/A   表只指向各仓 .ci/jenkins/repo/*-build.Jenkinsfile，不复制镜像串 → 无副本可漂移（SSOT-by-reference）"

echo
if [ "$fail" -eq 0 ]; then
  echo "RESULT: PASS"
  exit 0
else
  echo "RESULT: FAIL（见上 FAIL 行；修表或修源后重跑）"
  exit 1
fi
