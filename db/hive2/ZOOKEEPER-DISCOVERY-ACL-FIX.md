# ZooKeeper 动态发现 ACL 问题解决方案

## 问题描述

HiveServer2 无法通过 ZooKeeper 动态发现注册，错误信息：
```
AuthFailedException: KeeperErrorCode = AuthFailed for /hiveserver2
Error adding this HiveServer2 instance to ZooKeeper
```

虽然 HS2 客户端已成功通过 SASL 认证登录到 ZK，但在创建节点时 ACL 验证失败。

## 根本原因

1. **ACL 验证失败**：即使使用了 `sasl` scheme ACL，ZK 服务器在验证时可能仍有问题
2. **根节点 ACL 限制**：根节点 `/` 的 ACL 可能不允许创建子节点
3. **权限匹配问题**：HS2 使用的 principal 与 ZK 的 ACL 验证逻辑可能不匹配

## 成熟解决方案（基于网络搜索结果）

### 方案 1：手动创建节点并设置正确的 ACL（推荐）

#### 步骤 1：使用 ZK 管理员身份连接到 ZK

```bash
# 在 ZK 容器中执行
docker exec -it zookeeper-zoo1-1 bash

# 配置 JAAS（如果需要）
export JVMFLAGS="-Djava.security.auth.login.config=/conf/zk_server_jaas.conf"

# 连接到 ZK
/apache-zookeeper-3.5.10-bin/bin/zkCli.sh -server localhost:2181
```

#### 步骤 2：检查根节点的 ACL

```bash
[zk: localhost:2181(CONNECTED) 0] getAcl /
```

#### 步骤 3：如果需要，设置根节点的 ACL以允许创建子节点

```bash
# 设置根节点允许所有认证用户创建子节点
[zk: localhost:2181(CONNECTED) 0] setAcl / sasl:hive/hadoop@TEST.COM:cdrwa,world:anyone:r
```

#### 步骤 4：手动创建 /hiveserver2 节点并设置 ACL

```bash
# 创建节点
[zk: localhost:2181(CONNECTED) 0] create /hiveserver2 ""

# 设置 ACL（允许所有人读取，允许 HS2 的 principal 写入）
[zk: localhost:2181(CONNECTED) 0] setAcl /hiveserver2 sasl:hive/hadoop@TEST.COM:cdrwa,world:anyone:r

# 验证 ACL
[zk: localhost:2181(CONNECTED) 0] getAcl /hiveserver2
```

#### 步骤 5：重启 HS2，让它重新尝试注册

```bash
docker restart hiveserver2-hive2
```

### 方案 2：修改 ZK 配置以允许更宽松的 ACL（开发/测试环境）

#### 步骤 1：临时禁用 ZK 的 Kerberos 要求

编辑 `db/zookeeper/docker-compose.yml`：

```yaml
environment:
  # 注释掉 requireClientAuthScheme
  # ZOO_REQUIRE_CLIENT_AUTH_SCHEME: sasl
```

#### 步骤 2：重启 ZK

```bash
docker restart zookeeper-zoo1-1
```

#### 步骤 3：使用非 SASL 客户端手动创建节点

```bash
docker exec -it zookeeper-zoo1-1 /apache-zookeeper-3.5.10-bin/bin/zkCli.sh -server localhost:2181

[zk: localhost:2181(CONNECTED) 0] create /hiveserver2 ""
[zk: localhost:2181(CONNECTED) 0] setAcl /hiveserver2 world:anyone:cdrwa
```

#### 步骤 4：重新启用 Kerberos 要求并重启服务

```yaml
environment:
  ZOO_REQUIRE_CLIENT_AUTH_SCHEME: sasl
```

### 方案 3：检查并修复根节点的 ACL

如果根节点 `/` 的 ACL 不允许创建子节点，需要修改：

```bash
# 连接到 ZK（使用管理员身份）
docker exec -it zookeeper-zoo1-1 /apache-zookeeper-3.5.10-bin/bin/zkCli.sh -server localhost:2181

# 设置根节点 ACL 允许创建子节点
[zk: localhost:2181(CONNECTED) 0] setAcl / sasl:zookeeper/zoo1@TEST.COM:cdrwa,sasl:hive/hadoop@TEST.COM:cdrwa,world:anyone:r
```

## 已验证的配置

### 当前已完成的配置

1. ✅ ZK 服务器 JAAS 配置正确
2. ✅ Keytab 文件包含所有必要的主体
3. ✅ HS2 客户端已成功通过 SASL 认证登录到 ZK
4. ✅ 在 KDC 中创建了 `zookeeper/zoo1.test.com@TEST.COM` 主体

### 当前问题

- ❌ HS2 无法在 ZK 中创建 `/hiveserver2` 节点（ACL 验证失败）

## 推荐执行步骤

1. **首先尝试方案 1**：手动创建节点并设置正确的 ACL
2. **如果方案 1 失败**：尝试方案 2（临时禁用 Kerberos 要求）
3. **最后尝试方案 3**：检查并修复根节点的 ACL

## 参考资源

- [Azure HDInsight 故障排除指南](https://docs.azure.cn/zh-cn/hdinsight/interactive-query/interactive-query-troubleshoot-inaccessible-hive-view)
- [华为云 MRS 集群排错案例](https://bbs.huaweicloud.com/blogs/462191)
- [阿里云 EMR 负载均衡文档](https://help.aliyun.com/zh/emr/emr-on-ecs/user-guide/balance-the-load-of-hiveserver2)

