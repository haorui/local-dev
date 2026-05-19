# ZooKeeper ACL 验证逻辑版本分析

## 版本信息

### ZooKeeper 服务器版本
- **版本**：3.5.10
- **镜像**：`zookeeper:3.5.10`
- **配置位置**：`db/zookeeper/docker-compose.yml`

### HiveServer2 使用的 ZooKeeper 客户端版本
- **版本**：3.4.6（从 `zookeeper-3.4.6.jar` 推断）
- **位置**：`/opt/hive/lib/zookeeper-3.4.6.jar`
- **Hive 版本**：2.3.2

### Curator 版本（ZK 客户端框架）
- **版本**：需要检查具体版本
- **位置**：`/opt/hive/lib/curator-*.jar`

## 版本兼容性问题分析

### 关键发现

1. **版本差异**：
   - ZK 服务器：3.5.10（较新）
   - ZK 客户端：3.4.6（较老，Hive 2.3.2 自带）
   - 可能存在版本兼容性问题

2. **ACL Scheme 支持差异**：
   - ZooKeeper 3.4.6：主要支持 `auth` scheme 和 `AUTH_IDS`
   - ZooKeeper 3.5.10：增强了对 `sasl` scheme 的支持
   - 当服务器是 3.5.10 而客户端是 3.4.6 时，可能存在 ACL 验证逻辑差异

### 已知问题

#### 1. AUTH_IDS 在 Kerberized 环境中的限制

- **3.4.6 客户端行为**：
  - 默认使用 `AUTH_IDS`（`auth::cdrwa`）
  - 期望服务器能够将 `auth` scheme 映射到 SASL 认证的 principal

- **3.5.10 服务器行为**：
  - 支持 `sasl` scheme ACL
  - 当启用 `requireClientAuthScheme=sasl` 时，可能更严格地要求使用 `sasl` scheme
  - `auth` scheme 的映射可能不完全支持或有限制

#### 2. requireClientAuthScheme 的行为差异

在 ZooKeeper 3.5.x 中，`requireClientAuthScheme=sasl` 的行为：
- 要求所有客户端使用 SASL 认证
- 可能影响 ACL 验证逻辑
- 可能要求 ACL 使用 `sasl` scheme 而不是 `auth` scheme

#### 3. 根节点 ACL 的默认行为

- **非 Kerberized 环境**：根节点 `/` 默认 ACL 是 `world:anyone:cdrwa`
- **Kerberized 环境**：根节点的默认 ACL 可能不同
- **启用 requireClientAuthScheme 后**：根节点可能需要显式的 ACL 设置才能创建子节点

## ACL 验证逻辑检查点

### 1. 根节点 ACL

```bash
# 检查根节点的 ACL
[zk: localhost:2181(CONNECTED) 0] getAcl /
```

**问题**：如果根节点的 ACL 是 `world:anyone`，但 ZK 要求 SASL 认证，可能会有冲突。

### 2. ACL Scheme 匹配

- **HS2 创建的 ACL**：`world:anyone:r` + `auth::cdrwa` (AUTH_IDS) 或 `sasl:hive/hadoop@TEST.COM:cdrwa`（如果使用修改后的代码）
- **ZK 服务器期望**：当启用 `requireClientAuthScheme=sasl` 时，可能期望 `sasl` scheme ACL

### 3. 版本兼容性检查

- **客户端 3.4.6**：
  - 使用 `AUTH_IDS` 时，期望服务器能够映射到当前认证用户
  - 在 Kerberized 环境中，这可能需要服务器端的特殊支持

- **服务器 3.5.10**：
  - 增强了 SASL 支持
  - `auth` scheme 到 SASL principal 的映射可能有限制
  - 推荐使用 `sasl` scheme ACL

## 可能的解决方案

### 方案 1：升级 HS2 的 ZK 客户端版本

**问题**：这可能需要重新编译 Hive，不切实际。

### 方案 2：降级 ZK 服务器版本到 3.4.x

**可行性**：可以尝试，但可能失去 3.5.10 的一些功能。

### 方案 3：修改 ZK 配置，允许 `auth` scheme ACL

**检查点**：
- 是否可以通过配置让 ZK 3.5.10 接受 `auth` scheme ACL？
- 是否可以不使用 `requireClientAuthScheme`，只使用 `authProvider`？

### 方案 4：确保修改后的 HS2 代码使用 `sasl` scheme ACL

**当前状态**：已修改代码使用 `sasl:hive/hadoop@TEST.COM:cdrwa` ACL

**验证点**：确认修改后的代码确实被执行

### 方案 5：手动设置根节点 ACL

如果根节点的 ACL 不允许创建子节点，需要手动设置。

## 版本相关配置检查

### 检查 ZK 3.5.10 的配置选项

1. **authProvider**：`org.apache.zookeeper.server.auth.SASLAuthenticationProvider`
2. **requireClientAuthScheme**：`sasl`（如果启用）
3. **JVM 参数**：JAAS 配置

### 检查是否有版本相关的已知问题

- ZooKeeper 3.5.10 的 release notes
- Hive 2.3.2 与 ZooKeeper 3.5.x 的兼容性文档

## 推荐调试步骤

1. **检查根节点 ACL**（如果能够连接）
2. **尝试不使用 requireClientAuthScheme**，只使用 authProvider
3. **验证修改后的 HS2 代码确实使用了 sasl scheme ACL**
4. **检查 ZK 服务器日志中是否有 ACL 验证的详细信息**
5. **考虑降级到 ZK 3.4.x 测试兼容性**

## 参考资料

- [ZooKeeper 3.5.10 Release Notes](https://zookeeper.apache.org/doc/r3.5.10/releasenotes.html)
- [ZooKeeper 3.4.6 Release Notes](https://zookeeper.apache.org/doc/r3.4.6/releasenotes.html)
- [Hive 2.3.2 Compatibility](https://cwiki.apache.org/confluence/display/Hive/Configuration+Properties)

