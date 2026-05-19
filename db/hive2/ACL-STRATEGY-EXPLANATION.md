# HS2 Kerberos ACL 策略与 ZooKeeper ACL 策略详解

## 概述

本文档详细解释 HiveServer2 (HS2) 在 Kerberos 环境下如何为 ZooKeeper 节点创建 ACL，以及 ZooKeeper 的 ACL 机制，从而说明我们遇到的 `InvalidACL` 错误的根本原因。

---

## 1. ZooKeeper ACL 基础概念

### 1.1 ACL 结构

ZooKeeper 的 ACL 由三个部分组成：
- **Scheme（方案）**：认证方案，如 `world`、`auth`、`digest`、`ip`、`sasl`
- **ID（标识）**：具体的用户/实体标识
- **Permissions（权限）**：访问权限位（`READ`、`WRITE`、`CREATE`、`DELETE`、`ADMIN`）

### 1.2 ZooKeeper 支持的 ACL 方案

#### 1.2.1 `world` 方案
```
ACL: world:anyone:cdrwa
```
- **含义**：任何客户端都可以访问
- **使用场景**：非安全环境，开发/测试环境
- **示例**：`Ids.OPEN_ACL_UNSAFE` = `world:anyone:cdrwa`

#### 1.2.2 `auth` 方案
```
ACL: auth::cdrwa
```
- **含义**：使用"已认证的用户"（在会话建立后通过 `addauth` 添加的认证信息）
- **使用场景**：简单的用户名/密码认证
- **限制**：必须在使用 `auth` ACL 之前先调用 `addauth`

#### 1.2.3 `digest` 方案
```
ACL: digest:username:base64(SHA1(password)):cdrwa
```
- **含义**：基于用户名和密码摘要的认证
- **使用场景**：非 Kerberos 环境下的用户认证

#### 1.2.4 `sasl` 方案（Kerberos）
```
ACL: sasl:hive/hadoop@TEST.COM:cdrwa
```
- **含义**：基于 Kerberos/SASL 的认证，ID 部分是完整的 Kerberos principal
- **使用场景**：Kerberized 环境，生产环境推荐方案
- **特点**：ID 必须是完整的 Kerberos principal（如 `hive/hadoop@TEST.COM`）

#### 1.2.5 特殊的 `AUTH_IDS` ⚠️ 关键问题所在
```java
// ZooKeeper 源码中的定义
public static final Id AUTH_IDS = new Id("auth", "");  // scheme="auth", id=""
```

- **含义**：ZooKeeper 客户端库提供的特殊 ID，表示"所有已通过认证的用户"
- **Scheme**：使用 `auth` scheme（注意：不是 `sasl`）
- **ID**：空字符串 `""`
- **工作原理**：
  - 这是一个**客户端库层面的抽象**
  - 需要客户端在使用前调用 `zooKeeper.addAuthInfo(scheme, auth)` 提供认证信息
  - 服务器端会将 `auth::perms` 转换为对应 scheme 的实际 ID
- **问题**：在 Kerberized 环境中，认证是通过 SASL 在连接层面自动完成的，而不是通过 `addAuthInfo`

---

## 2. HS2 的 ACL 策略（Hive 2.3.2）

### 2.1 HS2 的 ACL 提供者实现

在 `HiveServer2.java` 中，HS2 使用 `ACLProvider` 为 ZooKeeper 节点提供 ACL：

```java
private final ACLProvider zooKeeperAclProvider = new ACLProvider() {
  @Override
  public List<ACL> getDefaultAcl() {
    List<ACL> nodeAcls = new ArrayList<ACL>();
    if (UserGroupInformation.isSecurityEnabled()) {
      // Read all to the world
      nodeAcls.addAll(Ids.READ_ACL_UNSAFE);  // world:anyone:r
      // Create/Delete/Write/Admin to the authenticated user
      nodeAcls.add(new ACL(Perms.ALL, Ids.AUTH_IDS));  // ⚠️ 问题所在
    } else {
      // ACLs for znodes on a non-kerberized cluster
      nodeAcls.addAll(Ids.OPEN_ACL_UNSAFE);  // world:anyone:cdrwa
    }
    return nodeAcls;
  }
};
```

### 2.2 HS2 ACL 策略的决策逻辑

HS2 根据 **Hadoop 安全模式**（`UserGroupInformation.isSecurityEnabled()`）来决定 ACL：

| Hadoop 安全模式 | HS2 ACL 策略 | 说明 |
|----------------|-------------|------|
| **启用**（Kerberos） | `world:anyone:r` + `AUTH_IDS:cdrwa` | 所有人可读，已认证用户可写 |
| **禁用** | `world:anyone:cdrwa` | 所有人可读写 |

### 2.3 `Ids.AUTH_IDS` 的含义

`Ids.AUTH_IDS` 是 ZooKeeper Java 客户端库提供的一个特殊 ID：

```java
// ZooKeeper 源码中的定义
public static final Id ANYONE_ID_UNSAFE = new Id("world", "anyone");
public static final Id AUTH_IDS = new Id("auth", "");  // ⚠️ 注意：scheme 是 "auth"，不是 "sasl"
```

**关键问题**：
- `AUTH_IDS` 使用 `auth` scheme，而不是 `sasl` scheme
- 在 Kerberized ZooKeeper 环境中，应该使用 `sasl` scheme
- 这导致 ZK 服务器在验证 ACL 时认为格式无效

---

## 3. ZooKeeper 服务器的 ACL 验证

### 3.1 Kerberized ZooKeeper 的 ACL 要求

当 ZooKeeper 服务器启用 SASL 认证时（通过 `ZOO_AUTH_PROVIDER_1` 和 `ZOO_REQUIRE_CLIENT_AUTH_SCHEME`），它期望：

1. **客户端使用 SASL 认证连接**：客户端必须通过 Kerberos 认证
2. **ACL 使用 `sasl` scheme**：znode 的 ACL 应该使用 `sasl:principal@REALM:perms` 格式

### 3.2 ACL 验证流程

当客户端尝试创建 znode 时：

```
1. 客户端通过 SASL 认证连接到 ZK（使用 Kerberos ticket）
2. 客户端请求创建 znode，并提供 ACL 列表
3. ZK 服务器验证 ACL：
   - 检查 ACL 的 scheme 是否被支持
   - 检查 ACL 的 ID 是否匹配当前认证的用户
   - 检查权限是否足够
4. 如果验证失败 → InvalidACL 异常
```

### 3.3 为什么 `AUTH_IDS` 会失败？🔍 核心问题分析

这是一个很好的问题：**`Ids.AUTH_IDS` 是 ZooKeeper 自己定义的类型，为什么不支持？**

让我们深入分析：

#### 3.3.1 `AUTH_IDS` 的设计意图

`AUTH_IDS` 的设计是为了支持**简单的认证模式**（如 `digest`），工作流程是：

```
1. 客户端连接到 ZK（无需认证）
2. 客户端调用：zooKeeper.addAuthInfo("digest", "username:password".getBytes())
3. 客户端创建 znode，使用 ACL: auth::cdrwa (AUTH_IDS)
4. ZK 服务器将 auth scheme 转换为 digest:username:hash，并验证权限
```

#### 3.3.2 在 Kerberized 环境中的问题

但在 **Kerberized 环境中**，认证流程完全不同：

```
1. 客户端通过 SASL 认证连接到 ZK（在连接建立时自动完成 Kerberos 认证）
2. 客户端创建 znode，使用 ACL: auth::cdrwa (AUTH_IDS)  ❌
3. ZK 服务器验证 ACL：
   - 发现 scheme 是 "auth"
   - 检查会话中是否有通过 addAuthInfo 添加的认证信息
   - 结果：没有！因为 Kerberos 认证是通过 SASL 在连接层面完成的
   - 返回 InvalidACL 错误
```

#### 3.3.3 详细的对比

| 认证方式 | 认证时机 | ACL Scheme | ACL ID | 是否兼容 `AUTH_IDS` |
|---------|---------|-----------|--------|-------------------|
| **Digest** | 连接后通过 `addAuthInfo` | `digest` | `username:hash` | ✅ 兼容（ZK 服务器会转换） |
| **SASL/Kerberos** | 连接建立时自动完成 | `sasl` | `principal@REALM` | ❌ **不兼容** |

#### 3.3.4 为什么 ZK 服务器拒绝 `AUTH_IDS`？

**HS2 提供的 ACL**：
```
[
  {scheme="world", id="anyone", perms=READ},      // ✅ 有效
  {scheme="auth", id="", perms=ALL}               // ❌ 问题
]
```

**ZK 服务器的验证逻辑**（在 Kerberized 环境中）：
```
1. 检查 ACL scheme: "auth"
2. 查找会话中的认证信息：
   - 检查是否有通过 addAuthInfo("auth", ...) 添加的信息 → 没有 ❌
   - 检查是否有通过 addAuthInfo("digest", ...) 添加的信息 → 没有 ❌
   - 检查是否有 SASL 认证信息 → 有，但 scheme 不匹配！❌
3. 结论：无法将 "auth" scheme 映射到具体的用户身份
4. 返回：InvalidACL 错误
```

**ZK 服务器期望的 ACL**（在 Kerberized 环境中）：
```
[
  {scheme="world", id="anyone", perms=READ},                    // ✅ 有效
  {scheme="sasl", id="hive/hadoop@TEST.COM", perms=ALL}        // ✅ 有效
]
```

#### 3.3.5 核心冲突总结

**关键问题**：
1. ✅ `AUTH_IDS` 本身是 ZooKeeper 官方定义的类型，**设计上没问题**
2. ❌ 但它是为**简单认证模式**（digest）设计的，不是为 **Kerberized 环境**设计的
3. ❌ 在 Kerberized 环境中，认证信息存储在 SASL 会话中，而不是通过 `addAuthInfo` 添加
4. ❌ ZK 服务器的 ACL 验证器无法将 `auth` scheme 映射到 SASL 认证的 principal

**类比理解**：
- `AUTH_IDS` 就像一把"万能钥匙"，但它只能打开通过"普通锁"认证的门
- Kerberized 环境使用的是"高级锁"（SASL），需要明确的"专用钥匙"（`sasl:principal:perms`）
- 虽然都是"钥匙"，但锁的类型不匹配！

---

## 4. 正确的 ACL 策略应该是怎样的？

### 4.1 在 Kerberized 环境中的正确做法

HS2 应该为每个 znode 设置明确的 `sasl` ACL：

```java
// 正确的 ACL 提供者实现（理想情况）
private List<ACL> createKerberosAcls() {
  List<ACL> nodeAcls = new ArrayList<ACL>();
  // 所有人可读
  nodeAcls.addAll(Ids.READ_ACL_UNSAFE);
  // 获取当前认证用户的 Kerberos principal
  String principal = UserGroupInformation.getLoginUser().getUserName();
  // 为当前用户设置 sasl ACL
  nodeAcls.add(new ACL(Perms.ALL, new Id("sasl", principal)));
  return nodeAcls;
}
```

### 4.2 LLAP 的实现（参考）

Hive 的 LLAP 组件使用了不同的 ACL 策略：

```java
private static List<ACL> createSecureAcls() {
  List<ACL> nodeAcls = new ArrayList<ACL>(ZooDefs.Ids.READ_ACL_UNSAFE);
  // 使用 CREATOR_ALL_ACL 而不是 AUTH_IDS
  nodeAcls.addAll(ZooDefs.Ids.CREATOR_ALL_ACL);
  return nodeAcls;
}
```

`CREATOR_ALL_ACL` 是另一个特殊 ID，表示"节点的创建者拥有所有权限"，这在某些情况下可能更兼容。

---

## 5. 我们遇到的问题总结

### 5.1 错误信息

```
KeeperErrorCode = InvalidACL for /hiveserver2
```

### 5.2 根本原因

| 组件 | 期望的 ACL | 实际提供的 ACL | 冲突点 |
|------|----------|--------------|--------|
| **ZooKeeper 服务器** | `sasl:hive/hadoop@TEST.COM:cdrwa` | `auth::cdrwa` | Scheme 不匹配（`auth` vs `sasl`） |
| **HS2 客户端** | 使用 `AUTH_IDS`（`auth` scheme） | - | 代码设计缺陷 |

### 5.3 为什么配置调整无法解决？

我们尝试了多种配置调整，但都失败了：

1. **版本匹配**：✅ 成功（ZK 3.5.10 兼容 Hive 2.3.2）
2. **移除强制 SASL 要求**：❌ 失败（HS2 仍尝试创建 `auth` scheme ACL）
3. **禁用 Hadoop 安全模式**：❌ 失败（HS2 会使用 `OPEN_ACL_UNSAFE`，但失去了 Kerberos 安全）
4. **禁用 ZK Kerberos**：❌ 失败（失去了安全目标）

**核心问题**：Hive 2.3.2 的代码逻辑硬编码了 `AUTH_IDS`，无法通过配置改变。

---

## 6. 解决方案对比

### 6.1 当前采用的方案（直连模式）

- **优点**：
  - ✅ 无需修改源码
  - ✅ HS2 可以正常工作
  - ✅ 满足代理开发需求
- **缺点**：
  - ❌ 无法使用 ZK 动态服务发现
  - ❌ 无法实现 HA（需要手动管理多个 HS2 实例）

### 6.2 源码级别修复（理想方案）

需要修改 `HiveServer2.java` 中的 `zooKeeperAclProvider`：

```java
// 修改前
nodeAcls.add(new ACL(Perms.ALL, Ids.AUTH_IDS));

// 修改后
String principal = hiveConf.getVar(ConfVars.HIVE_SERVER2_KERBEROS_PRINCIPAL);
nodeAcls.add(new ACL(Perms.ALL, new Id("sasl", principal)));
```

但这样做需要：
1. 修改 Hive 2.3.2 源码
2. 重新编译 Hive
3. 替换生产环境的 JAR 包（有风险）

### 6.3 代理层实现服务发现

如果代理需要 HA，可以在代理层实现自己的服务发现逻辑：
- 不使用 HS2 的 ZK 动态发现
- 代理直接连接多个 HS2 实例
- 代理层实现负载均衡和故障转移

---

## 7. 关键要点总结

### 7.1 ACL Scheme 的区别

| Scheme | 含义 | 使用场景 | ID 格式 |
|--------|------|---------|---------|
| `world` | 任何人都可以访问 | 非安全环境 | `anyone` |
| `auth` | 已认证的用户 | 简单认证 | 空字符串或用户名 |
| `sasl` | SASL/Kerberos 认证用户 | Kerberized 环境 | 完整的 Kerberos principal |

### 7.2 Hive 2.3.2 的设计缺陷

- **问题**：HS2 使用 `AUTH_IDS`（`auth` scheme）而不是 `sasl` scheme
- **原因**：代码设计时可能假设了非 Kerberized ZK 环境，或者对 ZK ACL 机制理解不足
- **影响**：在 Kerberized ZK 环境中无法使用动态服务发现

### 7.3 最佳实践

对于 Kerberized 环境：
- ✅ ZooKeeper 节点 ACL 应使用 `sasl:principal@REALM:perms` 格式
- ✅ ACL 的 ID 部分必须是完整的 Kerberos principal
- ❌ 避免使用 `AUTH_IDS` 这种抽象 ID
- ❌ 避免使用 `auth` scheme（在 Kerberized 环境中）

---

## 8. 参考资料

- [ZooKeeper ACL 文档](https://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#sc_ZooKeeperAccessControl)
- [HiveServer2 ZK Dynamic Discovery](https://cwiki.apache.org/confluence/display/Hive/AdminManual+MetastoreAdmin#AdminManualMetastoreAdmin-HiveServer2DynamicServiceDiscovery)
- Hive 2.3.2 源码：`service/src/java/org/apache/hive/service/server/HiveServer2.java`

---

**文档创建时间**：2025-12-03  
**相关 Issue**：HS2 + Kerberized ZK 的 `InvalidACL` 错误

