#!/bin/bash
# Hive 2.x 快速开始脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 路径定义
WORKSPACE_ROOT="/Users/haoruili/Documents/workspaces/sso/ucc-workspace"
KERBEROS_DIR="${WORKSPACE_ROOT}/kerberos"
KRB5_CONF="${KERBEROS_DIR}/client/krb5.conf"
CLI_KEYTAB="${KERBEROS_DIR}/data/keytabs/cli.keytab"

echo -e "${GREEN}=== Hive 2.x 快速开始 ===${NC}"
echo ""

# 1. 检查服务状态
echo -e "${YELLOW}1. 检查服务状态...${NC}"

# 检查 KDC
if docker ps | grep -q "krb5-kdc-server"; then
    echo -e "${GREEN}✅ KDC 正在运行${NC}"
else
    echo -e "${RED}❌ KDC 未运行，请先启动：${NC}"
    echo "   cd ${WORKSPACE_ROOT}/kerberos"
    echo "   docker compose up -d"
    exit 1
fi

# 检查 ZooKeeper
if docker ps | grep -q "zookeeper-zoo1-1"; then
    echo -e "${GREEN}✅ ZooKeeper 正在运行${NC}"
else
    echo -e "${YELLOW}⚠️  ZooKeeper 未运行，启动中...${NC}"
    cd "${WORKSPACE_ROOT}/db/zookeeper"
    docker compose up -d
    sleep 5
fi

# 检查 HiveServer2
cd "${WORKSPACE_ROOT}/db/hive2"
if docker ps | grep -q "hiveserver2-hive2"; then
    echo -e "${GREEN}✅ HiveServer2 正在运行${NC}"
else
    echo -e "${RED}❌ HiveServer2 未运行，请先启动：${NC}"
    echo "   cd ${WORKSPACE_ROOT}/db/hive2"
    echo "   docker compose up -d"
    exit 1
fi

# 2. 获取 Kerberos ticket
echo ""
echo -e "${YELLOW}2. 获取 Kerberos ticket...${NC}"
export KRB5CCNAME=FILE:/tmp/krb5cc_cli_beeline
export KRB5_CONFIG="${KRB5_CONF}"

if [ -f "${CLI_KEYTAB}" ]; then
    kinit -kt "${CLI_KEYTAB}" cli@TEST.COM
    echo -e "${GREEN}✅ Kerberos ticket 已获取${NC}"
    klist | head -3
else
    echo -e "${RED}❌ Keytab 文件不存在：${CLI_KEYTAB}${NC}"
    exit 1
fi

# 3. 显示连接方式
echo ""
echo -e "${GREEN}3. 连接方式：${NC}"
echo ""
echo -e "${YELLOW}方式 A：直接连接 HS2${NC}"
echo "beeline -u \"jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM\" \\"
echo "  -Djava.security.krb5.conf=${KRB5_CONF} \\"
echo "  -Djavax.security.auth.useSubjectCredsOnly=false"
echo ""
echo -e "${YELLOW}方式 B：使用 ZooKeeper 动态发现（推荐）${NC}"
echo "beeline -u \"jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=hive/hadoop@TEST.COM\" \\"
echo "  -Djava.security.krb5.conf=${KRB5_CONF} \\"
echo "  -Djavax.security.auth.useSubjectCredsOnly=false"
echo ""

# 4. 测试连接（可选）
read -p "是否现在测试连接？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}正在测试连接...${NC}"
    beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
      -Djava.security.krb5.conf="${KRB5_CONF}" \
      -Djavax.security.auth.useSubjectCredsOnly=false \
      -e "show databases;" 2>&1 | grep -v "^SLF4J\|^Connecting\|^Connected\|^Closing\|^Beeline version"
fi

echo ""
echo -e "${GREEN}✅ 准备完成！${NC}"

