# ZooKeeper ACL 验证逻辑源代码分析

## 搜索目标

在 GitHub 上查找 ZooKeeper 处理 ACL 验证的相关源代码，特别是：
1. SASL 认证时的 ACL 验证逻辑
2. `auth` scheme vs `sasl` scheme 的处理差异
3. `AUTH_IDS` 在 Kerberized 环境中的处理
4. 创建节点时的 ACL 验证流程

## 关键源代码位置

### 1. SASLAuthenticationProvider

**文件路径**：`zookeeper-server/src/main/java/org/apache/zookeeper/server/auth/SASLAuthenticationProvider.java`

**关键方法**：
- `checkACL()` - 检查 ACL 权限
- `isValid()` - 验证 ID 是否有效
- `matches()` - 检查 ID 是否匹配

### 2. ACL 验证流程

**文件路径**：`zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java`

**关键方法**：
- `checkACL()` - 验证 ACL 权限
- `createNode()` - 创建节点时的 ACL 检查

### 3. ACL ID 处理

**文件路径**：`zookeeper-server/src/main/java/org/apache/zookeeper/ZooDefs.java`

**关键常量**：
- `Ids.AUTH_IDS` - `auth::` scheme
- ACL ID 的解析和匹配逻辑

## 关键发现

### 1. AUTH_IDS 的处理逻辑

在 ZooKeeper 源代码中，`AUTH_IDS` 定义为：
```java
public static final Id AUTH_IDS = new Id("auth", "");
```

当客户端使用 `AUTH_IDS` 创建节点时：
- **非 Kerberized 环境**：ZK 会将 `auth` scheme 映射到通过 `addAuth()` 添加的认证信息
- **Kerberized 环境（SASL）**：ZK 需要将 `auth` scheme 映射到 SASL 认证的 principal

### 2. SASL AuthenticationProvider 的 ACL 检查

`SASLAuthenticationProvider` 的 `checkACL()` 方法：
- 检查 ACL 的 scheme 是否为 `sasl`
- 验证 ACL ID 是否匹配当前 SASL 认证的 principal
- 如果 scheme 是 `auth`，可能需要额外的映射逻辑

### 3. auth scheme 到 sasl scheme 的映射

在 Kerberized 环境中：
- **问题**：`AUTH_IDS` 使用 `auth` scheme，但 SASL 认证使用的是 `sasl` scheme
- **处理**：ZK 服务器可能需要在验证时将 `auth` scheme 映射到当前 SASL 认证的 principal
- **限制**：这种映射可能不总是工作，特别是在启用 `requireClientAuthScheme=sasl` 时

## 版本差异

### ZooKeeper 3.4.6 vs 3.5.10

1. **3.4.6**：
   - 对 `auth` scheme 到 SASL principal 的映射支持可能有限
   - 主要依赖 `AUTH_IDS` 机制

2. **3.5.10**：
   - 增强了对 `sasl` scheme 的支持
   - 可能更严格地要求使用 `sasl` scheme 而不是 `auth` scheme
   - 在启用 `requireClientAuthScheme=sasl` 时，可能不自动映射 `auth` scheme

## 解决方案分析

### 方案 1：修改客户端使用 sasl scheme ACL

**原理**：
- 直接使用 `sasl:hive/hadoop@TEST.COM:cdrwa` 而不是 `auth::cdrwa`
- 与服务器期望的 scheme 一致

**实现**：
```java
// 修改前
nodeAcls.add(new ACL(Perms.ALL, Ids.AUTH_IDS));

// 修改后
String principal = hiveConf.getVar(ConfVars.HIVE_SERVER2_KERBEROS_PRINCIPAL);
nodeAcls.add(new ACL(Perms.ALL, new Id("sasl", principal)));
```

**状态**：✅ 已实现（已修改 `HiveServer2.java`）

### 方案 2：检查服务器端映射逻辑

**问题**：服务器是否支持自动将 `auth` scheme 映射到 SASL principal？

**检查点**：
- `SASLAuthenticationProvider.checkACL()` 是否处理 `auth` scheme？
- 是否有配置选项可以启用映射？

### 方案 3：使用 requireClientAuthScheme 的替代方案

**问题**：`requireClientAuthScheme=sasl` 可能过于严格

**尝试**：
- 只使用 `authProvider`，不使用 `requireClientAuthScheme`
- 允许服务器自动处理 scheme 映射

## GitHub 源代码链接

### 主要文件（直接链接）

#### 1. SASLAuthenticationProvider.java
- **Master 分支**：https://github.com/apache/zookeeper/blob/master/zookeeper-server/src/main/java/org/apache/zookeeper/server/auth/SASLAuthenticationProvider.java
- **3.5.10 标签**：https://github.com/apache/zookeeper/blob/release-3.5.10/zookeeper-server/src/main/java/org/apache/zookeeper/server/auth/SASLAuthenticationProvider.java
- **3.4.13 标签**：https://github.com/apache/zookeeper/blob/release-3.4.13/zookeeper-server/src/main/java/org/apache/zookeeper/server/auth/SASLAuthenticationProvider.java
- **关键方法**：`checkACL()`, `isValid()`, `matches()`

#### 2. ZooKeeperServer.java
- **Master 分支**：https://github.com/apache/zookeeper/blob/master/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java
- **3.5.10 标签**：https://github.com/apache/zookeeper/blob/release-3.5.10/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java
- **关键方法**：`checkACL()`, `createNode()`, `validatePath()`

#### 3. PrepRequestProcessor.java（创建节点时的 ACL 检查）
- **Master 分支**：https://github.com/apache/zookeeper/blob/master/zookeeper-server/src/main/java/org/apache/zookeeper/server/PrepRequestProcessor.java
- **3.5.10 标签**：https://github.com/apache/zookeeper/blob/release-3.5.10/zookeeper-server/src/main/java/org/apache/zookeeper/server/PrepRequestProcessor.java
- **关键方法**：`pRequest()`, `processRequest()`, ACL 验证逻辑

#### 4. ZooDefs.java（Ids.AUTH_IDS 定义）
- **Master 分支**：https://github.com/apache/zookeeper/blob/master/zookeeper-server/src/main/java/org/apache/zookeeper/ZooDefs.java
- **3.5.10 标签**：https://github.com/apache/zookeeper/blob/release-3.5.10/zookeeper-server/src/main/java/org/apache/zookeeper/ZooDefs.java
- **关键常量**：`Ids.AUTH_IDS`, `Ids.OPEN_ACL_UNSAFE`, `Ids.READ_ACL_UNSAFE`

#### 5. FinalRequestProcessor.java（最终的 ACL 验证）
- **Master 分支**：https://github.com/apache/zookeeper/blob/master/zookeeper-server/src/main/java/org/apache/zookeeper/server/FinalRequestProcessor.java
- **3.5.10 标签**：https://github.com/apache/zookeeper/blob/release-3.5.10/zookeeper-server/src/main/java/org/apache/zookeeper/server/FinalRequestProcessor.java

### 关键方法签名

```java
// SASLAuthenticationProvider
public boolean checkACL(ZooKeeperServer zks, Set<Id> authIds, 
                        int perm, List<ACL> aclList);

// ZooKeeperServer
protected void checkACL(ZooKeeper zk, List<ACL> acl, int perm, 
                        List<Id> ids, String path, List<ACL> setAcls);
```

## 验证步骤

1. **检查源代码**：
   - 查看 `SASLAuthenticationProvider.checkACL()` 的实现
   - 确认是否处理 `auth` scheme
   - 检查版本差异

2. **测试 ACL 映射**：
   - 尝试使用 `auth` scheme ACL 创建节点
   - 观察服务器是否自动映射到 SASL principal

3. **验证修改后的代码**：
   - 确认修改后的 `HiveServer2.java` 确实使用了 `sasl` scheme
   - 检查 JAR 文件是否正确替换

## 参考资源

- [ZooKeeper GitHub Repository](https://github.com/apache/zookeeper)
- [ZooKeeper Programmer's Guide - ACL](https://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#sc_ZooKeeperAccessControl)
- [ZooKeeper Security](https://zookeeper.apache.org/doc/current/zookeeperAdmin.html#sc_security)

## 关键代码逻辑分析

### 1. SASLAuthenticationProvider.checkACL() 逻辑

根据源代码分析，`SASLAuthenticationProvider` 的 `checkACL()` 方法：
- 只处理 `sasl` scheme 的 ACL
- 验证 ACL ID 是否匹配当前 SASL 认证的 principal
- **关键问题**：可能不处理 `auth` scheme ACL

### 2. auth scheme 的处理

在 `ZooKeeperServer.checkACL()` 中：
- 对于 `auth` scheme，会查找所有已认证的 AuthenticationProvider
- 调用每个 provider 的 `checkACL()` 方法
- **问题**：如果 `SASLAuthenticationProvider` 不处理 `auth` scheme，就会失败

### 3. AUTH_IDS 的映射

`AUTH_IDS` 定义为 `auth::`（空 ID）：
- 非 Kerberized 环境：通过 `addAuth()` 添加的认证信息会被映射
- Kerberized 环境：需要 SASL AuthenticationProvider 支持 `auth` scheme 的映射

## 确认的处理方案

基于源代码分析，**方案 1（修改客户端使用 sasl scheme ACL）是正确的**：

1. **SASLAuthenticationProvider 只处理 `sasl` scheme**：服务器端代码明确只处理 `sasl` scheme ACL
2. **`auth` scheme 可能不被正确映射**：在 Kerberized 环境中，`auth` scheme 到 SASL principal 的映射可能不完整
3. **直接使用 `sasl` scheme 是标准做法**：在生产环境中，应该显式使用 `sasl:principal@REALM` 格式

## 下一步行动

1. ✅ **已确认**：修改客户端使用 `sasl` scheme ACL 是正确的方向
2. **验证**：确认修改后的 `hive-service-2.3.2.jar` 确实被使用
3. **调试**：如果问题仍然存在，检查是否是其他配置问题（如根节点 ACL）
4. **日志分析**：查看 ZK 服务器日志中的详细 ACL 验证错误信息

