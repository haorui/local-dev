# Hive 2.x 已验证的工作环境使用指南

## ✅ 当前状态

**已完成并验证的工作**：
1. HiveServer2 成功注册到 Kerberized ZooKeeper ✅
2. InvalidACL 错误已修复 ✅  
3. HS2 支持 Kerberos 认证 ✅
4. ZK 动态发现已启用 ✅

## 服务连接方式

### 重要说明  

由于 Docker for Mac 的 UDP 端口转发问题，宿主机无法直接连接 KDC。建议使用以下两种方式：

### 方式 1：在容器内使用 beeline（推荐）

容器内的环境已完全配置好，可以直接使用：

```bash
# 进入 HS2 容器
docker exec -it hiveserver2-hive2 bash

# 在容器内连接（无需 Kerberos 认证，因为是本地连接）
beeline -u "jdbc:hive2://localhost:10000/default"

# 或者使用 Kerberos 认证
kinit -kt /opt/hive/conf/hive.keytab hive/hadoop@TEST.COM
beeline -u "jdbc:hive2://localhost:10000/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM"
```

### 方式 2：直接连接（不使用 Kerberos）

如果您的客户端工具支持 JDBC，可以使用以下连接：

```
jdbc:hive2://localhost:10020/default
```

**说明**：
- 端口 `10020` 已映射到 host
- 这种方式不使用 Kerberos 认证
- 适合开发和测试环境

### 方式 3：宿主机 KDC 连接（Docker for Mac 限制）

**已知问题**：
- Docker for Mac 的 UDP 端口转发存在已知问题
- Kerberos 默认使用 UDP 协议
- 宿主机无法通过 `127.0.0.1:8800` 获取 Kerberos ticket
- 容器内可以正常使用 `krb5-kdc-server:88`

**解决方案**：
- 使用容器内的 beeline 或直接 JDBC 连接
- 详见 `KDC-ACCESS-WORKAROUND.md`

## 验证服务状态

### 检查 HS2 是否注册到 ZK

```bash
docker logs hiveserver2-hive2 | grep "Created a znode on ZooKeeper"
```

**预期输出**：
```
Created a znode on ZooKeeper for HiveServer2 uri=...
```

### 检查 ZK 中的节点

```bash
docker exec zookeeper-zoo1-1 bash -c "echo 'ls /hiveserver2' | /apache-zookeeper-3.5.10-bin/bin/zkCli.sh -server localhost:2181 2>&1 | grep serverUri"
```

### 查看 HS2 日志

```bash
docker logs -f hiveserver2-hive2
```

## 基本 SQL 操作

在容器内连接后：

```sql
-- 查看数据库
show databases;

-- 使用数据库
use default;

-- 创建表
create table test (id int, name string);

-- 插入数据
insert into table test values (1, 'Alice'), (2, 'Bob');

-- 查询数据
select * from test;
```

## 服务管理

### 启动服务

```bash
# 启动 ZooKeeper
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/zookeeper
docker compose up -d

# 启动 HiveServer2
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
docker compose up -d
```

### 停止服务

```bash
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
docker compose down

cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/zookeeper
docker compose down
```

### 重启服务

```bash
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
docker compose restart hiveserver2
```

## 配置信息

- **HS2 端口**：`10020`（host）→ `10000`（container）
- **ZK 端口**：`2181`
- **ZK 命名空间**：`hiveserver2`
- **Kerberos Realm**：`TEST.COM`
- **HS2 Principal**：`hive/hadoop@TEST.COM`
- **数据目录**：`db/hive2/data/hive-warehouse`

## 已修复的问题

1. **InvalidACL 错误** ✅
   - 问题：ZK 无法处理 `sasl` scheme ACL
   - 解决：在 `zoo.cfg` 中添加 `authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider`

2. **ConnectionLoss 错误** ✅
   - 问题：HS2 无法连接到 ZK
   - 解决：修复 `docker-compose.yml` 中的 ZK IP 地址

3. **Debug 日志不显示** ✅
   - 问题：Log4j2 配置过滤了 DEBUG 日志
   - 解决：修改 `hive-log4j2.properties`

## 相关文档

- `VERIFICATION-COMPLETE.md` - 完整验证报告
- `ZOOKEEPER-FIX-SUCCESS.md` - ZK 配置修复说明
- `JAR-VERIFICATION-SUCCESS.md` - JAR 修改验证
- `ACL-STRATEGY-EXPLANATION.md` - ACL 策略说明

---

**最后更新**：2025-12-04
**状态**：已验证可用 ✅

