# ZooKeeper 连接问题调试和解决方案

## 问题描述

HS2 在尝试连接 ZooKeeper 时遇到 `ConnectionLoss` 错误：
- 连接尝试频繁（每秒一次）
- 显示 "Opening socket connection" 和 "GSSAPI"
- 但没有看到会话建立成功的记录
- 连接在建立阶段就失败或立即断开

## 连接流程分析

### 正常连接流程

```
1. 打开 socket 连接
   ↓
2. 进行 SASL 认证（GSSAPI）
   ↓
3. 会话建立（Session establishment complete）
   ↓
4. 状态变为 CONNECTED
   ↓
5. 可以执行操作（创建节点等）
```

### 当前失败的流程

```
1. 打开 socket 连接 ✅
   ↓
2. 准备进行 SASL 认证（GSSAPI）✅
   ↓
3. ❌ 连接断开/失败
   (没有看到会话建立)
```

## 可能的原因

### 1. SASL 认证失败

**症状**：
- 连接建立后立即断开
- 没有会话建立记录
- 可能看到 "AUTH_FAILED" 状态

**检查方法**：
- 查看 HS2 日志中的 SASL 错误
- 查看 ZK 日志中的认证失败记录
- 检查服务主体匹配

### 2. requireClientAuthScheme 过于严格

**当前配置**：
- `ZOO_REQUIRE_CLIENT_AUTH_SCHEME: sasl` 已启用

**可能影响**：
- 要求所有客户端必须通过 SASL 认证
- 如果认证过程有问题，连接会立即断开

**解决方案**：
- 临时禁用，只使用 `authProvider`
- 测试连接是否稳定

### 3. 会话超时配置

**当前配置**：
- ZK 默认：minSessionTimeout=4000ms, maxSessionTimeout=40000ms
- 会话超时：30 秒

**可能问题**：
- 如果连接建立时间过长，可能超时
- 需要增加超时时间

### 4. 网络问题

虽然 ping 和端口测试通过，但可能存在：
- 网络抖动
- 延迟过高
- Docker 网络问题

## 调试步骤

### 步骤 1：检查 SASL 认证状态

```bash
# 检查 HS2 日志
docker logs hiveserver2-hive2 2>&1 | grep -iE "SASL|auth.*fail|GSS"

# 检查 ZK 日志
docker logs zookeeper-zoo1-1 2>&1 | grep -iE "sasl|auth.*fail"
```

### 步骤 2：检查会话建立

```bash
# 查找会话建立记录
docker logs hiveserver2-hive2 2>&1 | grep -E "Session establishment|SyncConnected"
```

### 步骤 3：检查连接时间线

```bash
# 查看完整的连接流程
docker logs --tail 200 hiveserver2-hive2 2>&1 | grep -E "Opening|Session|CONNECTED|AUTH_FAILED"
```

### 步骤 4：临时禁用 requireClientAuthScheme

```yaml
# docker-compose.yml
environment:
  ZOO_AUTH_PROVIDER_1: org.apache.zookeeper.server.auth.SASLAuthenticationProvider
  # ZOO_REQUIRE_CLIENT_AUTH_SCHEME: sasl  # 临时注释
```

### 步骤 5：增加会话超时时间

```properties
# zoo.cfg
tickTime=2000
minSessionTimeout=10000
maxSessionTimeout=60000
```

## 解决方案

### 方案 1：调整 ZK 配置（推荐）

1. **禁用 requireClientAuthScheme**：
   - 只使用 `authProvider`，允许更灵活的认证

2. **增加会话超时时间**：
   - 给连接和认证更多时间

3. **重启 ZK 服务器**：
   ```bash
   docker restart zookeeper-zoo1-1
   ```

### 方案 2：检查服务主体匹配

确保：
- HS2 客户端查找的服务主体：`zookeeper/zoo1.test.com@TEST.COM`
- ZK 服务器使用的服务主体：`zookeeper/zoo1@TEST.COM`
- KDC 中存在匹配的主体

### 方案 3：启用 DEBUG 日志

增加日志详细程度，便于诊断：
- HS2 日志级别
- ZK 日志级别

### 方案 4：网络诊断

- 检查 Docker 网络配置
- 验证容器间通信
- 检查防火墙规则

## 推荐操作顺序

1. **首先尝试方案 1**：
   - 禁用 `requireClientAuthScheme`
   - 增加会话超时时间
   - 重启服务测试

2. **如果仍失败**：
   - 检查服务主体匹配
   - 启用 DEBUG 日志
   - 详细分析连接时间线

3. **如果连接成功**：
   - 验证 ACL 逻辑
   - 测试节点创建
   - 测试 ZK 动态发现

## 下一步

根据验证结果，选择最可能的解决方案并实施。

