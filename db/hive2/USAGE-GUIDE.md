# Hive 2.x 环境使用指南

## 环境概述

当前环境配置：

- **HiveServer2**：Kerberos 认证 + ZooKeeper 动态发现
- **ZooKeeper**：单节点，Kerberos/SASL 认证
- **Metastore**：内嵌在 HS2 中，直接连接 PostgreSQL
- **HDFS**：Kerberized（NameNode + DataNode）

## 快速开始

### 基础连接

### 在Linux快速启动beeline客户端

```bash
docker run -d \
  --name hive-client \
  --entrypoint "/bin/bash" \
  apache/hive:3.1.3 \
  -c "sleep infinity"

# direct
docker exec -it hive-client beeline -u jdbc:hive2://192.168.3.13:10000

# transport proxy
docker exec -it hive-client beeline -u "jdbc:hive2://192.168.3.13:11000/default;user=user_a;password=654321"

docker exec -it hive-client beeline -u "jdbc:hive2://192.168.3.13:11000/default -n user_a -p 654321"

```

#### 直连

- 本地连接：`beeline -u jdbc:hive2://localhost:10000`
- 容器内连接：`beeline -u jdbc:hive2://hiveserver2-standalone:10000`

#### Proxy

本地连接：

```bash
# user_a
# Test SELECT (Allowed)
beeline -u "jdbc:hive2://localhost:11000/default;user=user_a;password=654321" \
   -e "show databases;"
```

### 方式 1：使用快速开始脚本（推荐）

```bash
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
./quick-start.sh
```

脚本会自动：

1. 检查服务状态
2. 获取 Kerberos ticket
3. 显示连接命令
4. 可选：测试连接

### 方式 2：手动步骤

#### 1. 启动环境

```bash
# 启动 ZooKeeper
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/zookeeper
docker compose up -d

# 启动 HiveServer2（会自动等待 ZK 就绪）
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
docker compose up -d

# 检查服务状态
docker compose ps
```

#### 2. 获取 Kerberos Ticket

在客户端机器上（host）：

```bash
# 设置环境变量
export KRB5CCNAME=FILE:/tmp/krb5cc_cli_beeline
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf

# 使用 keytab 获取 ticket
kinit -kt /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/data/keytabs/cli.keytab cli@TEST.COM

# 验证 ticket
klist
```

#### 3. 连接方式

#### 方式 A：直接连接（不使用 ZK 动态发现）

**快速测试**：

```bash
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
export HADOOP_OPTS="-Djava.security.krb5.conf=$KRB5_CONFIG -Djavax.security.auth.useSubjectCredsOnly=false"

beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -e "show databases;"
```

#### 方式 B：使用 ZooKeeper 动态发现（推荐）

```bash
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
export HADOOP_OPTS="-Djava.security.krb5.conf=$KRB5_CONFIG -Djavax.security.auth.useSubjectCredsOnly=false"

beeline -u "jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
 -e "show databases;"
```

**快速测试**：

```bash
beeline -u "jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -e "show databases;"
```

**注意**：

- ZK 服务器在 `localhost:2181` 可访问（已映射到 host）
- ZK 命名空间：`hiveserver2`
- 使用 ZK 动态发现可以自动发现可用的 HS2 实例（支持 HA）

### 4. 基本操作

连接成功后，可以执行以下 SQL：

```sql
-- 查看数据库
show databases;

-- 使用数据库
use default;

-- 创建表
create table test_table (id int, name string);

-- 插入数据
insert into table test_table values (1, 'test');

-- 查询数据
select * from test_table;

-- 查看表结构
describe test_table;
```

**注意**：由于当前环境使用本地文件系统（`file:///`），数据文件会存储在：

- 容器内：`/user/hive/warehouse`
- 宿主机：`db/hive2/data/hive-warehouse`

## 配置说明

### HiveServer2 配置

- **端口**：`10020`（映射到 host 的 `10020`）
- **Kerberos Principal**：`hive/hadoop@TEST.COM`
- **ZK 命名空间**：`hiveserver2`
- **ZK Quorum**：`zoo1.test.com:2181`

### ZooKeeper 配置

- **端口**：`2181`（映射到 host 的 `2181`）
- **Kerberos Principal**：`zookeeper/zoo1.test.com@TEST.COM`
- **认证方式**：SASL/Kerberos

### 网络配置

- **Docker 网络**：`dev_db_network`（外部网络）
- **HS2 容器**：`hiveserver2-hive2`
- **ZK 容器**：`zookeeper-zoo1-1`

## 故障排查

### 1. 连接失败

**检查服务状态**：

```bash
# 检查 HS2 是否运行
docker logs hiveserver2-hive2 | tail -50

# 检查 ZK 是否运行
docker logs zookeeper-zoo1-1 | tail -50
```

**检查 Kerberos Ticket**：

```bash
klist
# 如果 ticket 过期，重新获取
kinit -kt /path/to/cli.keytab cli@TEST.COM
```

### 2. InvalidACL 错误

如果遇到 `InvalidACL` 错误：

1. 检查 ZK 配置：确认 `zoo.cfg` 包含 `authProvider.1`
2. 检查 ZK 日志：确认没有 `Missing AuthenticationProvider` 错误
3. 重启容器：`docker compose restart`

### 3. 认证失败

如果遇到认证失败：

1. 检查 keytab 文件是否存在
2. 检查 principal 是否正确
3. 检查 `krb5.conf` 配置
4. 检查 KDC 是否运行

## 高级用法

### 使用 DBeaver 连接

1. **创建新连接**：
   - 驱动：Hive
   - 主机：`localhost`
   - 端口：`10020`（直接连接）或 `2181`（ZK 动态发现）
   - 数据库：`default`

2. **JDBC URL**（直接连接）：

   ```
   jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM
   ```

3. **JDBC URL**（ZK 动态发现）：

   ```
   jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=hive/hadoop@TEST.COM
   ```

4. **JVM 参数**（在 DBeaver 连接设置中）：
   ```
   -Djava.security.krb5.conf=/path/to/krb5.conf
   -Djavax.security.auth.useSubjectCredsOnly=false
   ```

### 查看 ZK 中的 HS2 注册信息

```bash
# 进入 ZK 容器
docker exec -it zookeeper-zoo1-1 bash

# 使用 zkCli.sh（需要 Kerberos 认证）
/apache-zookeeper-3.5.10-bin/bin/zkCli.sh -server localhost:2181

# 查看 HS2 注册的节点
ls /hiveserver2
get /hiveserver2/serverUri=hiveserver2-hive2:10000;version=2.3.2;sequence=0000000009
```

## 验证清单

- [ ] ZK 服务运行正常
- [ ] HS2 服务运行正常
- [ ] HS2 成功注册到 ZK（查看日志：`Created a znode on ZooKeeper`）
- [ ] Kerberos ticket 已获取
- [ ] beeline 可以成功连接
- [ ] 可以执行基本 SQL 操作

## 相关文档

- `VERIFICATION-COMPLETE.md` - 验证完成报告
- `ZOOKEEPER-FIX-SUCCESS.md` - ZK 配置修复说明
- `JAR-VERIFICATION-SUCCESS.md` - JAR 验证报告
- `ACL-STRATEGY-EXPLANATION.md` - ACL 策略说明

---

**最后更新**：2025-12-04
