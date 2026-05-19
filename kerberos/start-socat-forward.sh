#!/bin/bash
# Socat UDP 转发脚本 - 用于解决 Docker for Mac UDP 端口转发问题

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Socat UDP 转发启动脚本 ===${NC}"
echo ""

# 1. 检查 socat 是否安装
if ! command -v socat &> /dev/null; then
    echo -e "${YELLOW}socat 未安装，正在安装...${NC}"
    if ! command -v brew &> /dev/null; then
        echo -e "${RED}错误：需要安装 Homebrew 才能安装 socat${NC}"
        echo "请访问：https://brew.sh"
        exit 1
    fi
    brew install socat
    echo -e "${GREEN}✅ socat 安装完成${NC}"
fi

# 2. 检查 KDC 容器是否运行
if ! docker ps | grep -q "krb5-kdc-server"; then
    echo -e "${RED}错误：KDC 容器未运行${NC}"
    echo "请先启动 KDC："
    echo "  cd $(dirname $0)"
    echo "  docker compose up -d"
    exit 1
fi

# 3. 获取 KDC 容器 IP
KDC_IP=$(docker inspect krb5-kdc-server 2>/dev/null | grep -A5 "IPAddress" | grep "IPAddress" | tail -1 | cut -d'"' -f4)

if [ -z "$KDC_IP" ]; then
    echo -e "${RED}错误：无法获取 KDC 容器 IP${NC}"
    exit 1
fi

echo -e "${GREEN}✅ KDC 容器 IP: ${KDC_IP}${NC}"

# 4. 检查端口 88 是否已被占用
if lsof -i :88 2>/dev/null | grep -q LISTEN; then
    echo -e "${YELLOW}⚠️  端口 88 已被占用，正在停止旧的 socat 进程...${NC}"
    pkill -f "socat.*UDP4-LISTEN:88" || true
    sleep 1
fi

# 5. 检查端口 88 是否被占用（macOS 系统服务可能占用）
USE_PORT=8888
if lsof -i :88 2>/dev/null | grep -q LISTEN; then
    echo -e "${YELLOW}⚠️  端口 88 被占用，使用端口 8888${NC}"
    USE_PORT=8888
else
    USE_PORT=88
fi

# 6. 启动 socat UDP 转发
echo -e "${YELLOW}正在启动 UDP 转发：localhost:${USE_PORT} -> ${KDC_IP}:88${NC}"
# 在后台启动 socat（使用详细日志模式）
socat -v UDP4-LISTEN:${USE_PORT},fork,reuseaddr UDP4:${KDC_IP}:88 > /tmp/socat-kdc.log 2>&1 &
SOCAT_PID=$!

# 等待一下确保启动成功
sleep 1

# 检查进程是否还在运行
if ps -p $SOCAT_PID > /dev/null; then
    echo -e "${GREEN}✅ Socat UDP 转发已启动（PID: ${SOCAT_PID}）${NC}"
    echo ""
    echo "转发配置："
    echo "  本地: localhost:${USE_PORT} (UDP)"
    echo "  目标: ${KDC_IP}:88 (KDC 容器)"
    echo ""
    echo -e "${YELLOW}⚠️  注意：krb5.conf 需要配置 kdc = 127.0.0.1:${USE_PORT}${NC}"
    echo ""
    echo "日志文件: /tmp/socat-kdc.log"
    echo ""
    
    # 保存 PID 到文件
    echo $SOCAT_PID > /tmp/socat-kdc.pid
    echo -e "${GREEN}PID 已保存到: /tmp/socat-kdc.pid${NC}"
else
    echo -e "${RED}❌ Socat 启动失败${NC}"
    echo "请查看日志: /tmp/socat-kdc.log"
    exit 1
fi

echo ""
echo -e "${GREEN}=== 下一步 ===${NC}"
echo ""
echo "1. 确保 krb5.conf 配置使用 localhost:${USE_PORT}"
echo "   当前配置: kdc = 127.0.0.1:${USE_PORT}"
echo ""
echo "2. 测试 kinit:"
echo "   export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf"
echo "   kinit -kt kerberos/data/keytabs/cli.keytab cli@TEST.COM"
