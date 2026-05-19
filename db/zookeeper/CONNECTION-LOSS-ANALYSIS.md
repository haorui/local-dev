# ConnectionLoss 问题详细分析

## 问题描述

HS2 在尝试注册到 ZooKeeper 时遇到 `ConnectionLoss` 错误：
```
org.apache.curator.CuratorConnectionLossException: KeeperErrorCode = ConnectionLoss
```

## 验证发现

### 1. 连接建立状态

- ✅ SASL 认证成功
- ✅ 连接建立成功
- ✅ 会话创建成功
- ❌ 连接在创建节点前断开

### 2. 会话超时

ZK 日志显示：
```
INFO [SessionTracker:ZooKeeperServer@437] - Expiring session 0x100104b6daa0000, 
    timeout of 30000ms exceeded
```

- **会话超时时间**：30 秒（30000ms）
- **问题**：连接建立后，在 30 秒内没有完成节点创建，导致会话过期

### 3. 可能的原因

#### 3.1 网络延迟
- 连接建立需要时间
- SASL 认证需要时间
- 创建节点操作可能在超时后才执行

#### 3.2 会话超时配置过短
- ZK 默认会话超时可能对复杂操作来说太短
- 需要增加会话超时时间

#### 3.3 连接不稳定
- 网络抖动导致连接断开
- Docker 网络问题

#### 3.4 重试机制问题
- Curator 的重试策略可能有问题
- 连接断开后重试间隔太长

## 解决方案

### 方案 1：增加会话超时时间

**ZK 服务器配置**：
```properties
# zoo.cfg
tickTime=2000
minSessionTimeout=10000  # 增加到 10 秒
maxSessionTimeout=60000  # 增加到 60 秒
```

**HS2 客户端配置**：
```xml
<property>
  <name>hive.zookeeper.session.timeout</name>
  <value>60000</value>
</property>
```

### 方案 2：检查网络配置

- 确保容器之间网络连通
- 检查防火墙规则
- 验证 DNS 解析

### 方案 3：优化连接流程

- 减少连接建立时间
- 优化 SASL 认证流程
- 加快节点创建操作

### 方案 4：检查 Curator 配置

- 增加重试次数
- 减少重试间隔
- 优化重试策略

## 下一步行动

1. **增加会话超时时间**（推荐）
   - 修改 ZK 配置
   - 修改 HS2 配置
   - 重启服务测试

2. **网络诊断**
   - 检查容器网络
   - 验证连通性
   - 检查延迟

3. **详细日志分析**
   - 启用 DEBUG 日志
   - 分析连接时间线
   - 找出断开的具体原因

## 关键发现更新

### unexpected error 详细分析

从错误堆栈分析发现：
```
WARN ClientCnxn - Session 0x0 for server null, unexpected error, closing socket connection
```

**错误位置**：
- 发生在 `doTransport()` 阶段
- 在连接握手过程中
- Socket 在连接过程中被关闭（`ClosedChannelException`）

**可能的原因**：
1. **服务器端主动关闭连接**：
   - ZK 服务器在握手阶段检测到问题
   - 主动关闭了连接
   - 可能是认证配置不匹配

2. **连接握手失败**：
   - ZK 协议握手过程失败
   - 导致连接无法建立

3. **SASL 认证初始化问题**：
   - SASL 客户端创建后，握手过程失败
   - 导致连接立即关闭

## 当前状态

- ✅ 所有基础配置正确
- ✅ JAR 文件已正确部署
- ✅ 网络连通性正常
- ⚠️  连接在握手阶段失败（unexpected error）
- ❌ 无法完成节点创建

## 参考

- [ZooKeeper Session Timeout](https://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkSessions)
- [Curator Connection Handling](https://curator.apache.org/curator-framework/index.html)

