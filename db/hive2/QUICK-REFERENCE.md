# Hive 2.x 快速参考

## 一键启动

```bash
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
./quick-start.sh
```

## 手动连接步骤

### 1. 获取 Kerberos Ticket

```bash
export KRB5CCNAME=FILE:/tmp/krb5cc_cli_beeline
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
kinit -kt /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/data/keytabs/cli.keytab cli@TEST.COM
```

### 2. 连接 HiveServer2

**直接连接**：
```bash
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -Djava.security.krb5.conf=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf \
  -Djavax.security.auth.useSubjectCredsOnly=false
```

**ZK 动态发现**：
```bash
beeline -u "jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -Djava.security.krb5.conf=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf \
  -Djavax.security.auth.useSubjectCredsOnly=false
```

## 常用命令

### 服务管理

```bash
# 启动服务
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
docker compose up -d

# 停止服务
docker compose down

# 查看日志
docker logs -f hiveserver2-hive2
docker logs -f zookeeper-zoo1-1

# 重启服务
docker compose restart hiveserver2
```

### 验证服务

```bash
# 检查 HS2 是否注册到 ZK
docker logs hiveserver2-hive2 | grep "Created a znode on ZooKeeper"

# 检查 ZK 中的节点
docker exec zookeeper-zoo1-1 bash -c "echo 'ls /hiveserver2' | /apache-zookeeper-3.5.10-bin/bin/zkCli.sh -server localhost:2181 2>&1 | grep -v '^WARN\|^Connecting\|^Session'"
```

## 配置信息

- **HS2 端口**：`10020`（host）→ `10000`（container）
- **ZK 端口**：`2181`
- **Kerberos Realm**：`TEST.COM`
- **HS2 Principal**：`hive/hadoop@TEST.COM`
- **ZK Namespace**：`hiveserver2`

## 数据存储

- **容器内路径**：`/user/hive/warehouse`
- **宿主机路径**：`db/hive2/data/hive-warehouse`

---

**详细文档**：`USAGE-GUIDE.md`

