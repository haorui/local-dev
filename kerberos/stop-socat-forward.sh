#!/bin/bash
# 停止 Socat UDP 转发

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}正在停止 Socat UDP 转发...${NC}"

# 从 PID 文件读取
if [ -f /tmp/socat-kdc.pid ]; then
    PID=$(cat /tmp/socat-kdc.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo -e "${GREEN}✅ 已停止 Socat 进程 (PID: ${PID})${NC}"
    else
        echo -e "${YELLOW}⚠️  PID ${PID} 对应的进程不存在${NC}"
    fi
    rm -f /tmp/socat-kdc.pid
else
    echo -e "${YELLOW}⚠️  未找到 PID 文件${NC}"
fi

# 也尝试通过进程名查找并停止（包括 88 和 8888 端口）
pkill -f "socat.*UDP4-LISTEN:8" && echo -e "${GREEN}✅ 已停止所有相关 Socat 进程${NC}" || echo -e "${YELLOW}未找到运行中的 Socat 进程${NC}"

echo -e "${GREEN}完成${NC}"
