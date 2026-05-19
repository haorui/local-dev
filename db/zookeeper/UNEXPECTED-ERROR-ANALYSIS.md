# Unexpected Error 深度分析

## 问题现象

HS2 在尝试连接 ZooKeeper 时，连接在握手阶段立即失败：

```
INFO  ClientCnxn - Opening socket connection to server zoo1.test.com/172.18.0.2:2181. 
      Will attempt to SASL-authenticate using Login Context section 'HiveZooKeeperClient'
DEBUG ZooKeeperSaslClient - creating sasl client: client=hive/hadoop@TEST.COM;
      service=zookeeper;serviceHostname=zoo1.test.com
WARN  ClientCnxn - Session 0x0 for server null, unexpected error, 
      closing socket connection and attempting reconnect
```

## 关键发现

### 1. 服务主体不匹配问题

**客户端查找的服务主体**：
- 连接地址：`zoo1.test.com:2181`
- 构造的服务主体：`zookeeper/zoo1.test.com@TEST.COM`

**服务器配置的服务主体**：
- 容器 hostname：`zoo1`
- JAAS 配置中的主体：`zookeeper/zoo1@TEST.COM`

**问题**：
- 客户端使用 FQDN（`zoo1.test.com`）查找服务主体
- 服务器使用短主机名（`zoo1`）配置服务主体
- **这两个不匹配，导致 SASL 认证失败**

### 2. SASL 认证流程

GSSAPI SASL 认证流程：
1. 客户端连接服务器
2. 客户端构造服务主体：`service/hostname@REALM`
3. 客户端从 KDC 请求服务票据（Service Ticket）
4. 客户端发送服务票据给服务器
5. 服务器验证服务票据

**失败点**：
- 步骤 3 或 4 失败
- 客户端查找 `zookeeper/zoo1.test.com@TEST.COM`，但该主体可能在 KDC 中不存在
- 或者服务器期望的主体是 `zookeeper/zoo1@TEST.COM`，但客户端提供的是不同的主体

### 3. 错误表现

- **Session 0x0**：会话未建立
- **Server null**：连接未完全建立
- **Unexpected error**：在连接握手阶段遇到错误
- **连接立即关闭**：服务器或客户端检测到认证失败，关闭连接

## 根本原因

**服务主体名称不匹配**：
- 客户端根据连接地址的主机名构造服务主体
- 服务器根据 JAAS 配置中的主体名进行验证
- 两者必须完全匹配，否则 SASL 认证失败

## 解决方案

### 方案 1：创建 FQDN 服务主体（推荐）

**步骤**：
1. 在 KDC 中创建 `zookeeper/zoo1.test.com@TEST.COM` 主体
2. 添加到 `zoo1.keytab` 文件
3. 更新 ZK 服务器 JAAS 配置使用 FQDN 主体

**优点**：
- 客户端连接可以使用 FQDN
- 符合 Kerberos 最佳实践（使用 FQDN）

**缺点**：
- 需要修改 KDC 和 keytab

### 方案 2：客户端使用短主机名

**步骤**：
1. 修改 HS2 的 ZK 连接配置，使用 `zoo1:2181` 而不是 `zoo1.test.com:2181`
2. 客户端会查找 `zookeeper/zoo1@TEST.COM`

**优点**：
- 不需要修改服务器配置
- 简单快速

**缺点**：
- 如果网络配置依赖 FQDN，可能有问题

### 方案 3：配置服务器使用 FQDN

**步骤**：
1. 修改容器 hostname 为 `zoo1.test.com`
2. 或者在 JAAS 配置中明确使用 FQDN 主体

**优点**：
- 客户端和服务器都使用 FQDN

**缺点**：
- 需要修改容器配置

## 验证步骤

### 1. 检查服务主体是否存在

```bash
# 检查 KDC 中的主体
docker exec kerberos-server kadmin.local -q 'listprincs' | grep zookeeper

# 应该看到：
# zookeeper/zoo1@TEST.COM
# 如果需要 FQDN：
# zookeeper/zoo1.test.com@TEST.COM
```

### 2. 检查 keytab 文件

```bash
# 检查服务器 keytab
docker exec zookeeper-zoo1-1 klist -kte /etc/security/keytabs/zookeeper.keytab

# 应该包含客户端查找的服务主体
```

### 3. 检查客户端连接配置

```bash
# 检查 HS2 的 ZK 连接配置
docker exec hiveserver2-hive2 cat /opt/hive/conf/hive-site.xml | grep -i zookeeper
```

## 推荐实施步骤

1. **首先验证问题**：
   - 确认客户端查找的服务主体
   - 确认服务器配置的服务主体
   - 确认 KDC 中存在的主体

2. **选择解决方案**：
   - 推荐方案 1（创建 FQDN 主体）
   - 或者方案 2（使用短主机名）

3. **实施修改**：
   - 创建/更新主体和 keytab
   - 更新配置
   - 重启服务

4. **验证修复**：
   - 观察连接是否成功
   - 检查会话是否建立
   - 验证 ZK 注册是否成功

## 相关配置

### ZK 服务器 JAAS 配置
```conf
Server {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  storeKey=true
  principal="zookeeper/zoo1@TEST.COM";  # 或 zookeeper/zoo1.test.com@TEST.COM
  ...
};
```

### HS2 客户端 JAAS 配置
```conf
HiveZooKeeperClient {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  principal="hive/hadoop@TEST.COM";
  ...
};
```

### HS2 ZK 连接配置
```xml
<property>
  <name>hive.zookeeper.quorum</name>
  <value>zoo1:2181</value>  <!-- 或 zoo1.test.com:2181 -->
</property>
```

## 参考

- [ZooKeeper SASL Authentication](https://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#sc_ZooKeeperSASLAuthentication)
- [Kerberos Service Principal Names](https://web.mit.edu/kerberos/krb5-1.5/krb5-1.5.4/doc/krb5-user/What-is-a-Kerberos-Principal_003f.html)
- [GSSAPI SASL Mechanism](https://tools.ietf.org/html/rfc4752)

